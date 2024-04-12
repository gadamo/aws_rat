#!/bin/bash

bold='\033[1m'
underline='\033[4m'
normal='\033[0m'

check_prerequisites() {
    # Check Bash version (Bash 4.0+)
    if [[ "${BASH_VERSION:0:1}" -lt 4 ]]; then
        echo "This script requires Bash version 4.0 or higher. You are using Bash $BASH_VERSION."
        return 1
    fi

    # Check for AWS CLI installation
    if ! command -v aws >/dev/null 2>&1; then
        echo "AWS CLI is not installed. Please install it and configure your credentials."
        return 1
    fi

    # Check for AWS CLI credentials configuration
    if [[ ! -f ~/.aws/credentials ]] && [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        echo "AWS credentials are not properly set. Please configure them in ~/.aws/credentials or set the AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY environment variables."
        return 1
    fi

    # Check for AWS SSM Session Manager Plugin installation
    if ! command -v session-manager-plugin >/dev/null 2>&1; then
        echo "AWS SSM Session Manager Plugin is not installed. Please install it to continue."
        return 1
    fi

    # Check for jq installation
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq is not installed. Please install jq to process JSON data."
        return 1
    fi

    #echo "All prerequisites are met. You are good to go!"
    return 0
}

# Execute the check
check_prerequisites || exit 1

# Check for AWS profile and default region
if [[ -n $AWS_PROFILE && -n $AWS_DEFAULT_REGION ]]; then
    echo "Using AWS profile and default region from environment variables."
elif [[ -n $AWS_ACCESS_KEY_ID && -n $AWS_SECRET_ACCESS_KEY ]]; then
    echo "Using AWS access key and secret from environment variables."
    
    # Check for session token if needed
    if [[ -n $AWS_SESSION_TOKEN ]]; then
        echo "Using AWS session token from environment variables."
    fi
else
    echo "INFO: AWS credentials or profile not properly set in environment variables."
    # Prompt the user to select a profile from the available ones in ~/.aws/credentials
    if [[ -z "$AWS_PROFILE" ]]; then
        profiles=$(grep -o ^"\[[^]]*\]" ~/.aws/credentials | sed 's/\[\(.*\)\]/\1/')
        readarray -t awsProfiles <<<"$profiles"
        echo "Please select a profile: "
        select AWS_PROFILE in "${awsProfiles[@]}"; do
            if [ -n "$AWS_PROFILE" ]; then
                echo "You selected $AWS_PROFILE"
                break
            else
                echo "Invalid selection. Please try again."
            fi
        done
        echo -e "INFO: You can skip step above running: ${bold}export AWS_PROFILE=$AWS_PROFILE${normal}"
    fi
    export AWS_PROFILE
fi

if [[ -z "$AWS_DEFAULT_REGION" ]]; then
    regions=$(aws --region us-east-1 ec2 describe-regions --query "Regions[].RegionName" | jq -r 'sort[]')
    # Prompt user to select a region
    echo "Select a region:"
    select region in $regions; do
        if [[ -n "$region" ]]; then
            AWS_DEFAULT_REGION=$region
            echo "Selected region: $AWS_DEFAULT_REGION"
            break
        else
            echo "Invalid selection, please try again."
        fi
    done
    echo -e "INFO: You can skip step above running: ${bold}export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION${normal}"
fi
export AWS_DEFAULT_REGION


# Main menu function
show_menu() {
    echo "Select a functionality:"
    echo "1) EC2 Shell (SSM)"
    echo "2) SSH via SSM"
    echo "3) ALB Port Forward"
    echo "4) Connect to ECS Container"
    echo "5) RDS Port Forward"
    echo "6) CloudWatch Log Tail"
    echo "7) Restart ECS Service"
    echo "8) Exit"
    printf "Enter your choice ${bold}[1-8]${normal}: "
    read -r choice
    case $choice in
        1) connect_to_ec2;;
        2) setup_port_forwarding_ssh;;
        3) setup_port_forwarding_alb;;
        4) connect_to_container;;
        5) setup_port_forwarding_rds;;
        6) tail_cloudwatch_logs;;
        7) restart_ecs_service;;
        8) exit 0;;
        *) echo "Invalid option"; show_menu;;
    esac
}

# Functionality 1
connect_to_ec2() {
    echo "Fetching EC2 instances..."
    EC2_INSTANCES=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].[InstanceId, Tags[?Key=='Name'].Value | [0]]" --output text)
    if [ -z "$EC2_INSTANCES" ]; then
        echo "No EC2 instances found."
        show_menu
        return
    fi

    echo "Available EC2 instances:"
    IFS=$'\n'
    select_option=1
    options=()
    for instance in $EC2_INSTANCES; do
        echo "$select_option) $instance"
        options+=("$instance")
        select_option=$((select_option + 1))
    done
    echo "$select_option) Go back"
    options+=("Go back")
    unset IFS
    read -p "Enter the number of the EC2 instance to connect to, or $select_option to go back: " instance_number

    if [ "$instance_number" -eq "$select_option" ]; then
        show_menu
        return
    fi

    target_instance=$(sed -n "${instance_number}p" <<< "$EC2_INSTANCES" | awk '{print $1}')

    if [ -n "$target_instance" ]; then
        echo "Starting SSM session to EC2 instance: $target_instance"
        aws ssm start-session --target $target_instance
    else
        echo "Invalid instance number selected."
    fi

    show_menu
}


# Functionality 2
setup_port_forwarding_ssh() {
    echo "Fetching EC2 instances..."
    EC2_INSTANCES=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].[InstanceId, Tags[?Key=='Name'].Value | [0]]" --output text)
    if [ -z "$EC2_INSTANCES" ]; then
        echo "No EC2 instances found."
        show_menu
        return
    fi

    echo "Available EC2 instances for SSH connection:"
    IFS=$'\n'
    select_option=1
    options=()
    for instance in $EC2_INSTANCES; do
        echo "$select_option) $instance"
        options+=("$instance")
        select_option=$((select_option + 1))
    done
    echo "$select_option) Go back"
    options+=("Go back")
    unset IFS
    read -p "Enter the number of the EC2 instance to connect to, or $select_option to go back: " instance_number

    if [ "$instance_number" -eq "$select_option" ]; then
        show_menu
        return
    fi
    target_instance=$(sed -n "${instance_number}p" <<< "$EC2_INSTANCES" | awk '{print $1}')

    if [ -n "$target_instance" ]; then
        # Generate a random port number > 1025 - $RANDOM is distributed between 0 and 32767
        local_port=$((RANDOM + 1025))
        echo "Setting up port forwarding on port $local_port and initiating SSH session to EC2 instance: $target_instance"
        aws ssm start-session --target $target_instance --document-name AWS-StartPortForwardingSession --parameters "{\"portNumber\":[\"22\"],\"localPortNumber\":[\"$local_port\"]}" &
        # Save the background process PID
        SSM_PID=$!
        # Wait for the port to be ready
        while ! nc -z localhost $local_port; do echo "Waiting for tunnel setup to complete..."; sleep 1; done
        # Display instructions
        echo -e "${bold}Tunnel ready:${normal} You can now access $target_instance SSH port on ${underline}${bold}localhost:${local_port}${normal}"
        echo -e "e.g.: ${underline}${bold}sftp -P $local_port ec2-user@localhost${normal}"
        echo -e "e.g.: ${underline}${bold}scp  -P $local_port ec2-user@localhost:/etc/shells /tmp/test${normal}"
        echo -e "e.g.: ${underline}${bold}ssh -p $local_port ec2-user@localhost${normal}"
        # Start the SSH session
        ssh -p $local_port ec2-user@localhost
        # SSH session has ended, now kill the SSM port forwarding session
        kill $SSM_PID
        echo "SSM port forwarding session terminated."
    else
        echo "Invalid instance number selected."
    fi

    show_menu
} 

# Functionality 3
setup_port_forwarding_alb() {
    echo "Fetching available ALBs..."
    ALBS_JSON=$(aws elbv2 describe-load-balancers --query "LoadBalancers[*].[DNSName, LoadBalancerArn]" --output json)
    if [ -z "$ALBS_JSON" ]; then
        echo "No ALBs found."
        show_menu
        return
    fi

    # Parse and display DNS names for selection, storing ARNs in an associative array
    declare -a DNS_NAMES
    declare -A DNS_ARN_MAP

    # Fill DNS_NAMES array and DNS_ARN_MAP associative array
    while IFS=$'\t' read -r dnsname arn; do
        DNS_NAMES+=("$dnsname")
        DNS_ARN_MAP["$dnsname"]=$arn
    done < <(jq -r '.[] | .[0] + "\t" + .[1]' <<< "$ALBS_JSON")

    echo "Available ALBs:"
    select option in "${DNS_NAMES[@]}" "Go back"; do
        if [[ -n $option ]]; then
            if [ "$option" == "Go back" ]; then
                show_menu
            fi
            alb_dnsname=$option
            alb_arn=${DNS_ARN_MAP[$alb_dnsname]}

            echo "Selected DNS Name: $alb_dnsname"
            echo "Selected ARN: $alb_arn"

            break
        else
            echo "Invalid option. Please select a valid option."
        fi
    done

    echo "Fetching listening ports for $alb_dnsname..."
    LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn $alb_arn --query "Listeners[*].Port" --output text)
    if [ -z "$LISTENERS" ]; then
        echo "No listeners found for $alb_dnsname."
        show_menu
        return
    fi

    echo "Available listening ports on $alb_dnsname:"
    select port in $LISTENERS "Go back"; do
        if [[ -n "$port" ]]; then
            if [ "$port" == "Go back" ]; then
                setup_port_forwarding_alb
            fi
            break        
        else
            echo "Invalid selection, please try again."
        fi
    done

    echo "Fetching EC2 instances..."
    EC2_INSTANCES=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].[InstanceId, Tags[?Key=='Name'].Value | [0]]" --output text)
    if [ -z "$EC2_INSTANCES" ]; then
        echo "No EC2 instances found."
        show_menu
        return
    fi

    echo "Available EC2 instances for port forwarding:"
    IFS=$'\n'
    select_option=1
    for instance in $EC2_INSTANCES; do
        echo "$select_option) $instance"
        select_option=$((select_option + 1))
    done
    unset IFS

    read -p "Enter the number of the EC2 instance to connect to via SSH: " instance_number
    #target_instance=$(echo "$EC2_INSTANCES" | sed -n "${instance_number}p" | awk '{print $1}')
    target_instance=$(sed -n "${instance_number}p" <<< "$EC2_INSTANCES" | awk '{print $1}')

    # Generate a random port number > 1025 - $RANDOM is distributed between 0 and 32767
    local_port=$((RANDOM + 1025))

    echo "Setting up port forwarding to $alb_dnsname:$port - via $target_instance"
    aws ssm start-session --target $target_instance --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{"portNumber":["'${port}'"],"localPortNumber":["'$local_port'"],"host":["'${alb_dnsname}'"]}' &

    # Save the background process PID
    SSM_PID=$!

    # Wait for the port to be ready
    while ! nc -z localhost $local_port; do sleep 1; done

    echo -e "${bold}Tunnel ready:${normal} You can now access $alb_dnsname:$port on ${underline}${bold}localhost:${local_port}${normal}"
    echo "Press enter to exit"; read

    # User session has ended, now kill the SSM port forwarding session
    kill $SSM_PID
    echo "SSM port forwarding session terminated."
    show_menu
}

# Global arrays for caching
declare -A container_map
declare -A instance_map
container_options=()

# Functionality 4
connect_to_container() {
    # Fetch data when global vars are empty (thus, use cache when already populated)
    if [ ${#container_options[@]} -eq 0 ]; then
        echo "Fetching ECS clusters..."
        clusters=$(aws ecs list-clusters --query 'clusterArns' --output text)
        if [ -z "$clusters" ]; then
            echo "No ECS clusters found."
            show_menu
            return
        fi

        for cluster_arn in $clusters; do
            echo "Processing cluster: $cluster_arn"
            ecs_instances=$(aws ecs list-container-instances --cluster "$cluster_arn" --query 'containerInstanceArns' --output text)
            for instance_arn in $ecs_instances; do
                ec2_instance_id=$(aws ecs describe-container-instances --cluster "$cluster_arn" --container-instances $instance_arn --query 'containerInstances[].ec2InstanceId' --output text)
                echo "Listing tasks on EC2 instance: $ec2_instance_id"
                tasks=$(aws ecs list-tasks --cluster "$cluster_arn" --container-instance "$instance_arn" --query 'taskArns' --output text)
                # Single call to describe all tasks
                tasks_details=$(aws ecs describe-tasks --cluster "$cluster_arn" --tasks $tasks --output json)
                # Parse JSON response to loop through each task and extract necessary details
                while IFS= read -r task; do
                    container_id=$(jq -r '.containers[0].runtimeId' <<< "$task")
                    container_name=$(jq -r '.containers[0].name' <<< "$task")
                    service_name=$(jq -r '.group | sub("^service:"; "")' <<< "$task")

                    if [ -n "$container_id" ] && [ -n "$ec2_instance_id" ]; then
                        option="$service_name:$container_name:$ec2_instance_id"
                        container_options+=("$option")
                        container_map["$option"]=$container_id
                        instance_map["$option"]=$ec2_instance_id
                    fi
                done < <(jq -c '.tasks[]' <<< "$tasks_details")
            done
        done
    fi

    if [ ${#container_options[@]} -eq 0 ]; then
        echo "No containers found in ECS clusters."
        show_menu
        return
    fi

    echo "Available containers:"
    select option in "${container_options[@]}" "Go back"; do
        if [ -n "$option" ]; then
            if [ "$option" == "Go back" ]; then
                show_menu
            fi
            break
        else
            echo "Invalid selection, please try again."
        fi
    done

    selected_container_id=${container_map["$option"]}
    selected_instance_id=${instance_map["$option"]}

    if [ -n "$selected_container_id" ] && [ -n "$selected_instance_id" ]; then
        echo "Connecting to container $selected_container_id on instance $selected_instance_id"
        aws ssm start-session --target "$selected_instance_id" \
            --document-name "AWS-StartInteractiveCommand" \
            --parameters command="sudo docker exec -ti $selected_container_id sh"
    else
        echo "Invalid selection."
    fi

    show_menu
}

# Functionality 5
setup_port_forwarding_rds() {
    echo "Fetching available RDS instances..."
    RDS_INSTANCES=$(aws rds describe-db-instances --query "DBInstances[*].[DBInstanceIdentifier, Endpoint.Address, Endpoint.Port]" --output text)
    if [ -z "$RDS_INSTANCES" ]; then
        echo "No RDS instances found."
        show_menu
        return
    fi

    # Initialize an array
    declare -a RDS_ARRAY

    # Read each line of output into the array
    readarray -t RDS_ARRAY <<< "$RDS_INSTANCES"

    echo "Available RDS instances:"
    select option in "${RDS_ARRAY[@]}" "Go back"; do
        if [[ -n $option ]]; then
            if [ "$option" == "Go back" ]; then
                show_menu
            fi
            # rds_identifier=$(echo "$option" | awk '{print $1}')
            # rds_endpoint=$(echo "$option" | awk '{print $2}')
            # rds_port=$(echo "$option" | awk '{print $3}')
            read rds_identifier rds_endpoint rds_port <<< "$option"

            echo "Selected RDS Instance: $rds_identifier"
            echo "Endpoint: $rds_endpoint"
            echo "Port: $rds_port"

            break
        else
            echo "Invalid option. Please select a valid option."
        fi
    done

    echo "Fetching EC2 instances..."
    EC2_INSTANCES=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].[InstanceId, Tags[?Key=='Name'].Value | [0]]" --output text)
    if [ -z "$EC2_INSTANCES" ]; then
        echo "No EC2 instances found."
        show_menu
        return
    fi

    echo "Available EC2 instances for port forwarding:"
    IFS=$'\n'
    select target_instance in $EC2_INSTANCES "Go back"; do
        if [[ -n $target_instance ]]; then
            if [ "$target_instance" == "Go back" ]; then
                setup_port_forwarding_rds
            fi
            #ec2_instance_id=$(echo "$target_instance" | awk '{print $1}')
            ec2_instance_id=$(awk '{print $1}' <<< "$target_instance")
            echo "Selected EC2 instance for tunneling: $ec2_instance_id"
            break
        else
            echo "Invalid selection, please try again."
        fi
    done
    unset IFS
    IFS=$'\n'
    select_option=1
    options=()
    for instance in $EC2_INSTANCES; do
        echo "$select_option) $instance"
        options+=("$instance")
        select_option=$((select_option + 1))
    done
    echo "$select_option) Go back"
    options+=("Go back")
    unset IFS

    read -p "Enter the number of the EC2 instance to connect to, or $select_option to go back: " instance_number

    if [ "$instance_number" -eq "$select_option" ]; then
        show_menu
        return
    fi


    # Generate a random local port number > 1025
    local_port=$((RANDOM + 1025))

    echo "Setting up port forwarding to RDS $rds_identifier at $rds_endpoint:$rds_port via EC2 instance $ec2_instance_id"
    aws ssm start-session --target $ec2_instance_id --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{"portNumber":["'${rds_port}'"],"localPortNumber":["'$local_port'"],"host":["'${rds_endpoint}'"]}' &

    # Save the background process PID
    SSM_PID=$!

    # Wait for the port to be ready
    while ! nc -z localhost $local_port; do sleep 1; done

    echo -e "${bold}Tunnel ready${normal}: You can now access RDS $rds_identifier on ${underline}${bold}localhost:${local_port}${normal}"
    echo "Press enter to exit"; read

    # User session has ended, now kill the SSM port forwarding session
    kill $SSM_PID
    echo "SSM port forwarding session terminated."
    show_menu
}

#Functionality 6
tail_cloudwatch_logs() {
    echo "Fetching available CloudWatch log groups..."
    LOG_GROUPS=$(aws logs describe-log-groups --query 'logGroups[*].logGroupName' --output text)
    if [ -z "$LOG_GROUPS" ]; then
        echo "No CloudWatch log groups found."
        show_menu
        return
    fi
    echo "Available CloudWatch log groups:"
    select log_group in $LOG_GROUPS "Go back"; do
        if [[ -n $log_group ]]; then
            if [ "$log_group" == "Go back" ]; then
                show_menu
            fi
            echo "Starting live tail for log group: $log_group"
            aws logs tail "$log_group" --follow
            break
        else
            echo "Invalid selection. Please select a valid log group."
        fi
    done
    show_menu
}

#Functionality 7
restart_ecs_service() {
    echo "Fetching ECS clusters..."
    clusters=$(aws ecs list-clusters --query 'clusterArns' --output text)
    if [ -z "$clusters" ]; then
        echo "No ECS clusters found."
        show_menu
        return
    fi
    declare -A service_map
    service_options=()
    for cluster_arn in $clusters; do
        #cluster_name=$(echo "$cluster_arn" | awk -F'/' '{print $2}')
        cluster_name=$(awk -F'/' '{print $2}' <<< "$cluster_arn")
        echo "Processing cluster: $cluster_name"
        services=$(aws ecs list-services --cluster "$cluster_arn" --query 'serviceArns' --output text)
        for service_arn in $services; do
            #service_name=$(echo "$service_arn" | awk -F'/' '{print $NF}')
            service_name=$(awk -F'/' '{print $NF}' <<< "$service_arn")
            option="$cluster_name/$service_name"
            service_options+=("$option")
            service_map["$option"]="$service_arn"
        done
    done
    if [ ${#service_options[@]} -eq 0 ]; then
        echo "No ECS services found."
        show_menu
        return
    fi
    echo "Available ECS services:"
    select option in "${service_options[@]}" "Go back"; do
        if [[ -n $option ]]; then
            if [ "$option" == "Go back" ]; then
                show_menu
            fi
            service_arn=${service_map["$option"]}
            account_id=$(awk -F':' '{print $5}' <<< "$service_arn")
            cluster_arn="arn:aws:ecs:$AWS_DEFAULT_REGION:$account_id:cluster/$option"
            cluster_arn="$(dirname $cluster_arn)"
            service_name=$(awk -F'/' '{print $NF}' <<< "$service_arn")
            echo "Restarting service $service_name in cluster $cluster_arn"
            aws ecs update-service --cluster "$cluster_arn" --service "$service_name" --force-new-deployment > /dev/null

            printf "Do you want to wait for the service to stabilize? ${bold}(y/n)${normal}"
            read -r answer

            if [[ $answer = [Nn]* ]]; then
                 echo "Not waiting for service $service_name to stabilize. You can always run on another terminal:"
                 echo -e "${bold}aws --profile $AWS_PROFILE --region $AWS_DEFAULT_REGION ecs wait services-stable --cluster \"$cluster_arn\" --services \"$service_name\"${normal}"
                 echo -e "or more detailed: ${bold}aws --profile $AWS_PROFILE --region $AWS_DEFAULT_REGION ecs describe-services --cluster \"$cluster_arn\" --services \"$service_name\" --query 'services[0].{events: events[0:3], deployments: deployments}'${normal}"
            fi
            if [[ $answer = [Yy]* ]]; then
                echo "Polling for service $service_name status..."
                while true; do
                    # Fetch the most recent events and service status
                    status_output=$(aws ecs describe-services --cluster "$cluster_arn" --services "$service_name" --query 'services[0].{events: events[0:3], deployments: deployments}')
                    deployments=$(jq -r '.deployments[] | select(.status=="PRIMARY") | "\(.id) \(.desiredCount)/\(.runningCount) \(.rolloutState)"' <<< "$status_output")
                    events=$(jq -r '.events[] | "\(.createdAt): \(.message)"' <<< "$status_output")

                    echo -e "${bold}Deployment status:${normal}"
                    echo "$deployments"
                    echo -e "${bold}Recent events:${normal}"
                    echo "$events"

                    # Check if service has stabilized
                    primary_deployment_rollout_state=$(awk '{print $3}' <<< "$deployments")
                    if [[ $primary_deployment_rollout_state == "COMPLETED" ]]; then
                        echo "Service $service_name has stabilized."
                        break
                    else
                        echo "Waiting for 30 seconds before polling again..."
                        sleep 30
                    fi
                done
            fi
            break
        else
            echo "Invalid selection. Please select a valid service."
        fi
    done
    show_menu
}

# Start the menu
show_menu

