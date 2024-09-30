# Jira Ticket Classification

## Overview

Jira Ticket Classification is an automated system designed to classify Jira tickets using Amazon Bedrock's AI capabilities. This project can be used with Jira Server exports, providing automation capabilities similar to those available in Jira Cloud.

## Features

- Automatically classifies Jira tickets based on their content
- Utilizes Amazon Bedrock for AI-powered classification
- Processes Jira ticket exports placed in S3
- Uses AWS Glue for data deduplication
- Designed to work with Jira Server exports

## How It Works

1. **Data Input**: Jira ticket exports are placed in the `/unprocessed` folder of the deployed S3 bucket.

2. **Data Processing**: The system processes the exported tickets.

3. **Bedrock Classification**: Ticket data is sent to Amazon Bedrock, which uses a pre-defined classification prompt to categorize each ticket.

4. **Deduplication**: AWS Glue ensures no duplicate classifications are processed, maintaining data integrity.

5. **Results**: Classification results are stored and can be used to update the original Jira tickets or for further analysis.

## Components

- **Lambda Function**: Handles the main logic for ticket processing and classification.
- **Amazon Bedrock**: Provides the AI model for ticket classification.
- **AWS Glue**: Manages data deduplication.
- **S3**: Stores Jira exports and classification results.

## Setup and Configuration

**Important Notice**: This project deploys resources in your AWS environment using Terraform. You will incur costs for the AWS resources used. Please be aware of the pricing for services like Lambda, Bedrock, Glue, and S3 in your AWS region.

**Required Permissions**: You need elevated permissions, specifically Power User permissions, to deploy the Terraform stack.

To set up the project:

1. Navigate to the `infrastructure` folder in the project.
2. Run `terraform init` to initialize the Terraform working directory.
3. Run `terraform apply` to create the resources in your AWS environment.

To tear down the project:

1. Navigate to the `infrastructure` folder.
2. Run `terraform destroy` to remove all resources created by this project.

## Usage

1. Export tickets from your Jira Server instance.
2. Place the exported ticket data in the `/unprocessed` folder of the S3 bucket created by the Terraform script.
3. The system will automatically process new files in this folder.
4. Retrieve classification results from the designated output location in S3.

## Requirements

- AWS Account with access to Lambda, Bedrock, Glue, and S3
- Terraform installed on your local machine
- Power User permissions in your AWS account
- Ability to export tickets from Jira Server (Jira Server instance not required)

## Contributing

Contributions to improve the project are welcome. Please feel free to submit pull requests or open issues to discuss potential enhancements.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Support

For support or to report issues, please open an issue in the project's GitHub repository.

---

For more detailed information on the implementation and architecture, please refer to the project documentation.