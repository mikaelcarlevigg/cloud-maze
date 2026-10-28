# Ser till att AWS CLI är inloggad i ditt eget konto. Läses in av de andra skripten.
#
# I CloudShell är du redan inloggad och inget frågas. Kör du från din egen dator
# och AWS CLI saknar inloggningsuppgifter, frågar skriptet efter dina nycklar.
# De gäller bara så länge skriptet körs och sparas aldrig på disk.

ensure_aws_credentials() {
  if ! command -v aws >/dev/null 2>&1; then
    echo "AWS CLI saknas. Installera det: https://aws.amazon.com/cli/"
    echo "Eller kör i AWS CloudShell, där allt redan finns."
    return 1
  fi

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "Hittar inga AWS-inloggningsuppgifter. Ange nycklarna för ditt eget konto."
    echo "De sparas inte på disk. Så skapar du nycklar: se 'Egna inloggningsuppgifter' i aws/README.md."
    echo
    read -rp "AWS Access Key ID: " AWS_ACCESS_KEY_ID
    read -rsp "AWS Secret Access Key (syns inte när du skriver): " AWS_SECRET_ACCESS_KEY; echo
    read -rp "Session token (tryck Enter om du inte har någon): " AWS_SESSION_TOKEN
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    if [ -n "$AWS_SESSION_TOKEN" ]; then export AWS_SESSION_TOKEN; else unset AWS_SESSION_TOKEN; fi
    # Keys from the prompt replace any profile that did not work.
    unset AWS_PROFILE

    if ! aws sts get-caller-identity >/dev/null 2>&1; then
      echo "Inloggningen misslyckades. Kontrollera nycklarna och försök igen."
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
