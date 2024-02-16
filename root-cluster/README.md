1. Install AWS CLI
2. Run `aws configure` and provide your key and secret (required to use backend state on Linode Object Store)
3. Copy `terrarform.tfvars.template` to `terrarform.tfvars` and update variables with required access credentials
4. Run `terraform init`
5. Run `terraform apply`.