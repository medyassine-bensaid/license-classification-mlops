from kfp import dsl

@dsl.pipeline(
    name="License Classification Ultimate MLOps Pipeline",
    description="A modular, validated, and GitOps-driven pipeline for training and deploying the license classification model."
)
def license_pipeline(
    config_path: str = "/app/config/params.yaml", # Default path inside containers
    feast_repo_path: str = "/app/feature_repo",
    template_path: str = "/app/k8s/seldon-deployment-template.yaml",
    deployment_namespace: str = "staging-models",
    model_stage: str = "Staging",
    docker_registry_prefix: str = "yourdockerhubusername",
    gitops_manifest_repo_ssh_url: str = "git@github.com:your-username/mlops-manifests.git",
    bento_image_tag: str = "latest"
):
    # ========================== Step 1: Generate Training Data from Feast ==========================
    generate_data_op = dsl.ContainerOp(
        name="generate-training-data",
        image=f"{docker_registry_prefix}/01_generate_training_data:{bento_image_tag}",
        arguments=[
            "--feast_repo", feast_repo_path,
            "--output", "/app/training_dataset.csv"
        ],
        file_outputs={"training_data": "/app/training_dataset.csv"}
    )

    # ========================== Step 2: Validate Data (QUALITY GATE 1) ==========================
    validate_data_op = dsl.ContainerOp(
        name="validate-data",
        image=f"{docker_registry_prefix}/02_validate_data:{bento_image_tag}",
        arguments=[
            "--reference_data", generate_data_op.outputs["training_data"], # In a real scenario, this would be a fixed reference file
            "--new_data", generate_data_op.outputs["training_data"],
            "--report", "/app/validation_report.json"
        ],
        file_outputs={"report": "/app/validation_report.json"}
    ).after(generate_data_op)

    # ========================== Step 3: Train and Package Model with BentoML ==========================
    train_op = dsl.ContainerOp(
        name="train-and-package-model",
        image=f"{docker_registry_prefix}/03_train_and_package:{bento_image_tag}",
        arguments=[
            "--config", config_path,
            "--data", validate_data_op.inputs.parameters['new_data'],
            "--bento_tag_output", "/app/bento_tag.txt"
        ],
        # Outputs for downstream components
        file_outputs={
            "mlflow_run_id": "/app/mlflow_run_id.txt",
            "bento_tag": "/app/bento_tag.txt"
        }
    ).after(validate_data_op)
    
    # ========================== Step 4: Validate Model (QUALITY GATE 2) ==========================
    validate_model_op = dsl.ContainerOp(
        name="validate-model-performance",
        image=f"{docker_registry_prefix}/04_validate_model:{bento_image_tag}",
        arguments=[
            "--config", config_path,
            "--run_id", train_op.outputs["mlflow_run_id"],
            "--test_data", validate_data_op.inputs.parameters['new_data'] # Using the same data for simplicity, ideally a held-out test set
        ]
    ).after(train_op)

    # ========================== Step 5: Promote Model and Trigger GitOps ==========================
    trigger_gitops_op = dsl.ContainerOp(
        name="promote-model-and-trigger-gitops",
        image=f"{docker_registry_prefix}/05_promote_and_trigger:{bento_image_tag}",
        arguments=[
            "--config", config_path,
            "--run_id", train_op.outputs["mlflow_run_id"],
            "--stage", model_stage,
            "--bento_tag", train_op.outputs["bento_tag"]
        ]
    ).after(validate_model_op)
    # Mount the Git SSH key to allow pushing to the manifest repo
    trigger_gitops_op.add_pvolumes({
        "/root/.ssh": dsl.PipelineVolume(secret=dsl.Secret(secret_name="gitops-ssh-secret"))
    })