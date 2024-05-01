#!/bin/sh
# POSIX compatible launcher script to:
# - Find the latest version of Bash on the system
# - Check prerequisite packages are installed
# - Check env vars are present, or prompt the user to select
# - Finally, run the main script

# Define a list of potential bash paths
BASH_PATHS="/bin/bash /usr/bin/bash /usr/local/bin/bash"

# Add the Session Manager Plugin path to the PATH
export PATH="$PATH:/usr/local/sessionmanagerplugin/bin/"

find_latest_bash() {
    latest_bash=""
    latest_version=0
    for path in $BASH_PATHS; do
        if [ -x "$path" ]; then
            # shellcheck disable=SC2016 # Fetch major version number using the bash -c command 
            version=$("$path" -c 'echo "${BASH_VERSINFO[0]}"') 
            if [ "$version" -gt "$latest_version" ]; then
                latest_version=$version
                latest_bash=$path
            fi
        fi
    done
    echo "$latest_bash"
}

check_prerequisites() {
    # Check Bash version (Bash 4.0+)
    # shellcheck disable=SC2016
    version=$("$LATEST_BASH" -c 'echo "${BASH_VERSINFO[0]}"')
    if [ "$version" -lt 4 ]; then
        echo "This script requires Bash version 4.0 or higher. Version of $LATEST_BASH is $version."
        return 1
    fi

    # Check for AWS CLI installation
    if ! command -v aws >/dev/null 2>&1; then
        echo "AWS CLI is not installed. Please install it and configure your credentials."
        return 1
    fi

    # Check for AWS CLI credentials configuration
    if [ ! -f ~/.aws/credentials ] && { [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; }; then
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

    return 0
}

# Select AWS profile from available profiles
select_aws_profile() {
    profiles=$(grep -o "^\[[^]]*\]" ~/.aws/credentials | sed 's/\[\(.*\)\]/\1/')
    i=1
    echo "Please select a profile:"
    for profile in $profiles; do
        echo "$i) $profile"
        eval "awsProfiles_$i=$profile"
        i=$((i + 1))
    done

    while true; do
        printf "Enter number (1-%d): " "$((i - 1))"
        read -r num
        if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -lt "$i" ] 2>/dev/null; then
            eval "AWS_PROFILE=\$awsProfiles_$num"
            echo "You selected $AWS_PROFILE"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
    export AWS_PROFILE
    echo "INFO: You can skip step above running: export AWS_PROFILE=$AWS_PROFILE"
}

# Select AWS region from available regions
select_aws_region() {
    regions=$(aws --region us-east-1 ec2 describe-regions --query "Regions[].RegionName" | jq -r 'sort[]')
    i=1
    echo "Select a region:"
    for region in $regions; do
        echo "$i) $region"
        eval "regionList_$i=$region"
        i=$((i + 1))
    done

    while true; do
        printf "Enter number (1-%d): " "$((i - 1))"
        read -r num
        if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -lt "$i" ] 2>/dev/null; then
            eval "AWS_DEFAULT_REGION=\$regionList_$num"
            echo "Selected region: $AWS_DEFAULT_REGION"
            break
        else
            echo "Invalid selection, please try again."
        fi
    done
    export AWS_DEFAULT_REGION
    echo "INFO: You can skip step above running: export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION"
}

# Main function to check AWS credentials and profile setup
check_aws_credentials() {
    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "INFO: Using AWS access key and secret from environment variables."
        if [ -n "$AWS_SESSION_TOKEN" ]; then
            echo "INFO: Using AWS session token from environment variables."
        fi
        return 0
    fi

    if [ -z "$AWS_PROFILE" ]; then
        select_aws_profile
    fi

    if [ -z "$AWS_DEFAULT_REGION" ]; then
        select_aws_region
    fi

    if [ -n "$AWS_PROFILE" ] && [ -n "$AWS_DEFAULT_REGION" ]; then
        echo "INFO: Using AWS profile and default region from environment variables."
        return 0
    fi
    return 1
}


# Locate the most recent bash
LATEST_BASH=$(find_latest_bash)

# Check if a suitable Bash was found
if [ -z "$LATEST_BASH" ]; then
    echo "Bash is required to run this script."
    echo "Please install Bash and rerun this script."
    exit 1
fi

# Execute the checks
check_prerequisites && check_aws_credentials || exit 1

# Get the path to the current script, resolving possible symlinks
script_path=$(dirname "$0")

# Convert to absolute path if necessary
case "$script_path" in
    /*)
        ;;
    *)
        script_path=$(pwd)/$script_path
        ;;
esac

# Execute the main script with the found Bash
"$LATEST_BASH" "${script_path}/aws_resource_access_tool.sh" "$@"