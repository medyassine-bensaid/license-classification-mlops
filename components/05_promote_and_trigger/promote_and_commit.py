import argparse
import mlflow
import yaml
from git import Repo
import tempfile
import os

def promote_and_trigger(config_path: str, run_id: str, model_stage: str, bento_tag: str):
    with open(config_path) as f:
        config = yaml.safe_load(f)

    model_name = config['deployment']['model_name']
    mlflow_uri = config['mlflow_tracking_uri']
    mlflow.set_tracking_uri(mlflow_uri)
    client = mlflow.tracking.MlflowClient()

    print(f"Promoting model from run '{run_id}' to stage '{model_stage}'...")
    model_version = client.create_model_version(
        name=model_name,
        source=f"runs:/{run_id}/model",
        run_id=run_id
    )
    client.transition_model_version_stage(
        name=model_name,
        version=model_version.version,
        stage=model_stage,
        archive_existing_versions=True
    )
    print(f"Successfully promoted model version {model_version.version} to '{model_stage}'.")

    with tempfile.TemporaryDirectory() as repo_dir:
        print(f"Cloning manifest repository...")
        manifest_repo_ssh_url = config['deployment']['gitops_manifest_repo_ssh_url']
        # The container needs an SSH key mounted to authenticate
        Repo.clone_from(manifest_repo_ssh_url, repo_dir)
        repo = Repo(repo_dir)

        namespace = f"{'prod' if model_stage == 'Production' else 'staging'}-models"
        deployment_dir = os.path.join(repo_dir, "deployments", 'production' if model_stage == 'Production' else 'staging')
        os.makedirs(deployment_dir, exist_ok=True)
        deployment_yaml_path = os.path.join(deployment_dir, f"{model_name.lower()}.yaml")
        
        with open("/app/k8s/seldon-deployment-template.yaml") as f:
            template = f.read()

        deployment_name = f"{model_name.lower()}-{model_stage.lower()}"
        bento_image = f"{config['docker_registry']}/{config['deployment']['bento_service_name']}:{bento_tag}"
        
        manifest = template.replace("__DEPLOYMENT_NAME__", deployment_name)
        manifest = manifest.replace("__NAMESPACE__", namespace)
        manifest = manifest.replace("__BENTO_IMAGE__", bento_image)

        with open(deployment_yaml_path, 'w') as f:
            f.write(manifest)

        print("Committing and pushing updated manifest to GitOps repo...")
        repo.index.add([deployment_yaml_path])
        commit_message = f"Update {model_stage} deployment for {model_name} to version {model_version.version} (Bento: {bento_tag})"
        repo.index.commit(commit_message)
        origin = repo.remote(name='origin')
        origin.push()
        print("GitOps trigger complete.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--run_id", required=True)
    parser.add_argument("--stage", required=True)
    parser.add_argument("--bento_tag", required=True)
    args = parser.parse_args()
    promote_and_trigger(
        config_path=args.config,
        run_id=args.run_id,
        model_stage=args.stage,
        bento_tag=args.bento_tag
    )