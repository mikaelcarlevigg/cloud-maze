# Makes sure the AWS CLI is signed in to your own account. Sourced by the other scripts.
#
# In CloudShell you are already signed in and nothing is asked. If you run from your
# own computer and the AWS CLI has no credentials, the script asks for your keys.
# They are only used while the script runs and are never saved to disk.

ensure_aws_credentials() {
  if ! command -v aws >/dev/null 2>&1; then
    echo "The AWS CLI is missing. Install it: https://aws.amazon.com/cli/"
    echo "Or run in AWS CloudShell, where everything is already set up."
    return 1
  fi

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "No AWS credentials found. Enter the keys for your own account."
    echo "They are not saved to disk. To create keys, see 'Your own credentials' in aws/README.md."
    echo
    read -rp "AWS Access Key ID: " AWS_ACCESS_KEY_ID
    read -rsp "AWS Secret Access Key (hidden as you type): " AWS_SECRET_ACCESS_KEY; echo
    read -rp "Session token (press Enter if you have none): " AWS_SESSION_TOKEN
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    if [ -n "$AWS_SESSION_TOKEN" ]; then export AWS_SESSION_TOKEN; else unset AWS_SESSION_TOKEN; fi
    # Keys from the prompt replace any profile that did not work.
    unset AWS_PROFILE

    if ! aws sts get-caller-identity >/dev/null 2>&1; then
      echo "Sign-in failed. Check the keys and try again."
      unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
      return 1
    fi
  fi

  if [ -z "${AWS_REGION:-}" ] && [ -z "$(aws configure get region 2>/dev/null)" ]; then
    read -rp "Region [eu-north-1]: " AWS_REGION
    AWS_REGION="${AWS_REGION:-eu-north-1}"
  fi
  if [ -n "${AWS_REGION:-}" ]; then export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"; fi

  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  export AWS_ACCOUNT_ID
}

aws_region() {
  echo "${AWS_REGION:-$(aws configure get region 2>/dev/null)}"
}
