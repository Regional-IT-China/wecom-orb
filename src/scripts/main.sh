#!/bin/sh
# shellcheck disable=SC2016,SC3043

# Import utils.
eval "$SLACK_SCRIPT_UTILS"
JQ_PATH=/usr/local/bin/jq

#BuildMessageBody() {
#
#    if [ "$CCI_STATUS" = "pass" ]; then TEMPLATE="\$basic_success_1"
#    elif [ "$CCI_STATUS" = "fail" ]; then TEMPLATE="\$basic_fail_1"
#    else echo "A template wasn't provided nor is possible to infer it based on the job status. The job status: '$CCI_STATUS' is unexpected."; exit 1
#    fi
#
#    template_body="$(eval printf '%s' \""$TEMPLATE\"")"
#    SanitizeVars "$template_body"
#
#    # shellcheck disable=SC2016
#    T1="$(printf '%s' "$template_body" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/`/\\`/g')"
#    T2="$(eval printf '%s' \""$T1"\")"
#
#    WECOM_MSG_BODY="$T2"
#}

PostToWecom() {
    echo "Sending notification to Wecom group..."
    WECOM_MSG_BODY="{\"msgtype\": \"text\", \"text\": {\"content\": \"this is a notification message from circleci\"}}"
    WECOM_SENT_RESPONSE=$(curl -s -f -X POST -H 'Content-type: application/json' --data "$WECOM_MSG_BODY" https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key="$WECOM_ACCESS_TOKEN")

    WECOM_ERROR_MSG=$(echo "$WECOM_SENT_RESPONSE" | jq '.errmsg')
    if [ ! "$WECOM_ERROR_MSG" = "null" ]; then
        echo "Wecom API returned an error message:"
        echo "$WECOM_ERROR_MSG"
        echo
        echo
        echo "View the Setup Guide: https://github.com/Regional-IT-China/wecom-orb/wiki/Setup"
    fi
}

InstallJq() {
    echo "Checking For JQ + CURL"
    if command -v curl >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
        uname -a | grep Darwin > /dev/null 2>&1 && JQ_VERSION=jq-osx-amd64 || JQ_VERSION=jq-linux32
        curl -Ls -o "$JQ_PATH" https://github.com/stedolan/jq/releases/download/jq-1.6/"${JQ_VERSION}"
        chmod +x "$JQ_PATH"
        command -v jq >/dev/null 2>&1
        return $?
    else
        command -v curl >/dev/null 2>&1 || { echo >&2 "WECOM ORB ERROR: CURL is required. Please install."; exit 1; }
        command -v jq >/dev/null 2>&1 || { echo >&2 "WECOM ORB ERROR: JQ is required. Please install"; exit 1; }
        return $?
    fi
}

CheckEnvVars() {
    if [ -z "${WECOM_ACCESS_TOKEN:-}" ]; then
        echo "In order to use the Wecom Orb, an token must be present via the WECOM_ACCESS_TOKEN environment variable."
        echo "Follow the setup guide available in the wiki: https://github.com/Regional-IT-China/wecom-orb/wiki/Setup"
        exit 1
    fi
}


# $1: Template with environment variables to be sanitized.
SanitizeVars() {
  [ -z "$1" ] && { printf '%s\n' "Missing argument."; return 1; }
  local template="$1"

  # Find all environment variables in the template with the format $VAR or ${VAR}.
  # The "|| true" is to prevent bats from failing when no matches are found.
  local variables
  variables="$(printf '%s\n' "$template" | grep -o -E '\$\{?[a-zA-Z_0-9]*\}?' || true)"
  [ -z "$variables" ] && { printf '%s\n' "Nothing to sanitize."; return 0; }

  # Extract the variable names from the matches.
  local variable_names
  variable_names="$(printf '%s\n' "$variables" | grep -o -E '[a-zA-Z0-9_]+' || true)"
  [ -z "$variable_names" ] && { printf '%s\n' "Nothing to sanitize."; return 0; }

  # Find out what OS we're running on.
  detect_os

  for var in $variable_names; do
    # The variable must be wrapped in double quotes before the evaluation.
    # Otherwise the newlines will be removed.
    local value
    value="$(eval printf '%s' \"\$"$var\"")"
    [ -z "$value" ] && { printf '%s\n' "$var is empty or doesn't exist. Skipping it..."; continue; }

    printf '%s\n' "Sanitizing $var..."

    local sanitized_value="$value"
    # Escape backslashes.
    sanitized_value="$(printf '%s' "$sanitized_value" | awk '{gsub(/\\/, "&\\"); print $0}')"
    # Escape newlines.
    sanitized_value="$(printf '%s' "$sanitized_value" | awk 'NR > 1 { printf("\\n") } { printf("%s", $0) }')"
    # Escape double quotes.
    if [ "$PLATFORM" = "windows" ]; then
        sanitized_value="$(printf '%s' "$sanitized_value" | awk '{gsub(/"/, "\\\""); print $0}')"
    else
        sanitized_value="$(printf '%s' "$sanitized_value" | awk '{gsub(/\"/, "\\\""); print $0}')"
    fi

    # Write the sanitized value back to the original variable.
    # shellcheck disable=SC3045 # This is working on Alpine.
    printf -v "$var" "%s" "$sanitized_value"
  done

  return 0;
}

# Will not run if sourced from another script.
# This is done so this script may be tested.
ORB_TEST_ENV="bats-core"
if [ "${0#*"$ORB_TEST_ENV"}" = "$0" ]; then
    # shellcheck source=/dev/null
    . "/tmp/WECOM_JOB_STATUS"
    CheckEnvVars
    InstallJq
    PostToWecom
fi
