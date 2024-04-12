# aws_rat

AWS Remote Access Tool: Streamlined access to AWS resources via CLI and SSM

## Description

AWS Remote Access Tool (aws_rat) is a bash script designed to facilitate secure and efficient access to private AWS resources through the AWS CLI and SSM. It is designed for developers and system administrators who need an easy way to perform remote operations on various AWS resources, such as EC2, ALB, ECS, and RDS. It allows users to perform actions like opening a shell on EC2 instances, port forwarding, and tailing CloudWatch logs. For shell access and port forwardings, SSM is used to establish access.

## Prerequisites

- AWS IAM permissions to access the resources
- Bash environment
- AWS CLI installed and configured with a profile defined in your `~/.aws/credentials` file.
- AWS SSM Session Manager Plugin for AWS CLI
- jq (Command-line JSON processor)

## Installation

1. Download the `aws_resource_access_tool.sh` script to your local machine.
2. Make the script executable: `chmod +x aws_resource_access_tool.sh`

## Usage

Run the script using `./aws_resource_access_tool.sh`. Upon starting, the script will prompt you to select an AWS profile and region. You can skip these prompts by setting the `AWS_PROFILE` and `AWS_DEFAULT_REGION` environment variables before running the script.

```bash
export AWS_PROFILE=your_profile_name
export AWS_DEFAULT_REGION=your_region
./aws_resource_access_tool.sh
```

The script provides the following functionalities:

* EC2 Shell (SSM): Opens an interactive shell on an EC2 instance using AWS SSM.
* SSH via SSM: Sets up SSH access to an EC2 instance through SSM.
* ALB Port Forward: Establishes port forwarding through an Application Load Balancer.
* Connect to ECS Container: Connects to a running ECS container instance.
* RDS Port Forward: Sets up port forwarding for an RDS database instance.
* CloudWatch Log Tail: Tails logs from a specified CloudWatch log group.
* Restart ECS Service: Restarts a service running on ECS.

Select the desired functionality by entering the corresponding number.

## License

This script is released under the MIT License.
