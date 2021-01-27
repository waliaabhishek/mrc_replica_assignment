#!/bin/bash

show_usage () {
    echo "Usage: $0 [options [parameters]]"
    echo ""
    echo "Options:"
    echo "    --help -- Prints this page"
    echo "    --dry-run -- Allows you to test all lthe configs and confirm that your command file bootstrap servers are working"
    echo "    --bootstrap-server [bootstrap-server-list]"
    echo "    --command-config [command-config-file]"
    echo "    --replica-placement-filepath [replica-placement-filepath]"
    echo "    --describe-all-topics-only -- Use this switch to skip all the other activities and only describe all the topics in the cluster for verification."

    return 0
}

if [[ $# -eq 0 ]];then
   echo "No input arguments provided which is not supported"
   show_usage
   exit 1
fi

echo "============================================================================"
DRY_RUN_ENABLED=false
ONLY_DESCRIBE_TOPICS=false

while [ ! -z "$1" ]
do
    if [[ "$1" == "--help" ]]
    then
        show_usage
        exit 0
    elif [[ "$1" == "--bootstrap-server" ]]
    then
        if [[ "$2" == --* ]] || [[ -z "$2" ]]
        then
            echo "No Value provided for "$1". Please ensure proper values are provided"
            show_usage
            exit 1
        fi
        SCRIPT_BOOTSTRAP_SERVERS="$2"
        echo "Bootstrap Servers are: ${SCRIPT_BOOTSTRAP_SERVERS}"
        shift
    elif [[ "$1" == "--command-config" ]]
    then
        if [[ "$2" == --* ]] || [[ -z "$2" ]]
        then
            echo "No Value provided for "$1". Please ensure proper values are provided"
            show_usage
            exit 1
        fi
        SCRIPT_COMMAND_CONFIG="$2"
        echo "Command Config File path is: ${SCRIPT_COMMAND_CONFIG}"
        shift
    elif [[ "$1" == "--replica-placement-filepath" ]]
    then
        if [[ "$2" == --* ]] || [[ -z "$2" ]]
        then
            echo "No Value provided for "$1". Please ensure proper values are provided"
            show_usage
            exit 1
        fi
        SCRIPT_REPLICA_PLACEMENT_FILE_NAME="$2"
        echo "Replica Placement file is: ${SCRIPT_REPLICA_PLACEMENT_FILE_NAME}"
        shift
    elif [[ "$1" == "--dry-run" ]]
    then
        DRY_RUN_ENABLED=true
        echo "Dry run is currently enabled"
    elif [[ "$1" == "--describe-all-topics-only" ]]
    then
        ONLY_DESCRIBE_TOPICS=true
        echo "Only the topics will be described. If Dry run is enabled, this step will not be executed."
    fi
    shift
done

SCRIPT_TOPIC_FILE_NAME=(${PWD}/`date +"%s"`_alltopics.txt)
EXECUTION_TOPIC_FILE_NAME=(${PWD}/`date +"%s"`_filterlist.txt)

if [[ -z "$SCRIPT_BOOTSTRAP_SERVERS"  ]] || [[ -z "$SCRIPT_REPLICA_PLACEMENT_FILE_NAME"  ]]
then
    echo "--bootstrap-server and --replica-placement-filepath are required for execution."
    show_usage
    exit 1
fi

if [[ "$DRY_RUN_ENABLED" = true ]]
then 
    echo "Fetching the list of topics to ensure that all settings are working properly"
    echo "============================================================================"
    if [[ -z "${SCRIPT_COMMAND_CONFIG}" ]]
    then
        echo "Executing without Command Config"
        kafka-topics  --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --list
    else
        echo "Executing with Command Config"
        kafka-topics  --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --command-config ${SCRIPT_COMMAND_CONFIG} --list
    fi
    echo "============================================================================"
    echo "Ensure that all the topics are listed in the above output. If some topics are missing, the current user provided in the command config does not have full permissions."
    echo "If Confluent RBAC is enabled, ensure that the user is SystemAdmin to allow all necessary operations."
    echo "============================================================================"
    echo "This script does not validate the Replica placement file for correctness. Please ensure that the file is correct before removing the druy run switch."
    echo "Please find below the contents of the Replica Placement file: "
    cat ${SCRIPT_REPLICA_PLACEMENT_FILE_NAME}
    echo "============================================================================"
    exit 0
fi 

echo "============================================================================"
echo "Getting the list of topics"
if [[ -z "${SCRIPT_COMMAND_CONFIG}" ]]
then
    echo "Executing without Command Config"
    kafka-topics  --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --list > ${SCRIPT_TOPIC_FILE_NAME}
else
    echo "Executing with Command Config"
    kafka-topics  --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --command-config ${SCRIPT_COMMAND_CONFIG} --list > ${SCRIPT_TOPIC_FILE_NAME}
fi

if [[ "$ONLY_DESCRIBE_TOPICS" == true ]]
then
    echo "============================================================================"
    echo "Describing all topics"
    cat ${SCRIPT_TOPIC_FILE_NAME} | while read topic_name
    do
        if [[ -z "${SCRIPT_COMMAND_CONFIG}" ]]
        then
            echo "Executing without Command Config"
            kafka-topics --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --topic ${topic_name} --describe
        else
            echo "Executing with Command Config"
            kafka-topics --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --command-config ${SCRIPT_COMMAND_CONFIG} --topic ${topic_name} --describe
        fi
    done
    rm ${SCRIPT_TOPIC_FILE_NAME}
    echo "============================================================================"
    exit 0
fi

echo "============================================================================"
echo "The output of this step is available in ${SCRIPT_TOPIC_FILE_NAME}"
echo "If there are multiple unwanted lines due to some issues in java execution, remove them from the file before proceedding to the next step."
echo "============================================================================"

read -p "Press enter to continue once you have validated the file and are happy to proceed further."

echo "============================================================================"
echo "============================================================================"

cat ${SCRIPT_TOPIC_FILE_NAME} | while read topic_name
do
    echo "======================"
    echo "Checking ${topic_name}"
    if [[ -z "${SCRIPT_COMMAND_CONFIG}" ]]
    then
        OUTPUT_TOPIC_NAME=$(kafka-topics --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --topic ${topic_name} --describe | grep "Configs:" | grep -v "confluent.placement.constraints={" | awk '{print $2}')
    else
        OUTPUT_TOPIC_NAME=$(kafka-topics --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --command-config ${SCRIPT_COMMAND_CONFIG} --topic ${topic_name} --describe | grep "Configs:" | grep -v "confluent.placement.constraints={" | awk '{print $2}')
    fi
    if [[ -z "$OUTPUT_TOPIC_NAME" ]]
    then
        echo "topic ${topic_name} already has MRC configs. Skipping"
    else
        echo "topic ${topic_name} does not have MRC configs. Update necessary."
        echo "Adding to execution list."
        echo ${OUTPUT_TOPIC_NAME} >> ${EXECUTION_TOPIC_FILE_NAME}
    fi
done
echo "============================================================================"
echo "The output of this step is available in ${EXECUTION_TOPIC_FILE_NAME}"
echo "Validation complete. Check and remove the topics that you would not like to enable for MRC from the file."
echo "============================================================================"

read -p "Press enter to continue once you have validated the file and are happy to proceed further."

echo "============================================================================"

cat ${EXECUTION_TOPIC_FILE_NAME} | while read topic_name
do
    echo "Working on ${topic_name}"
    if [[ -z "${SCRIPT_COMMAND_CONFIG}" ]]
    then
        echo "Executing without Command Config"
        kafka-configs --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --entity-type topics --entity-name ${topic_name} --alter --replica-placement ${SCRIPT_REPLICA_PLACEMENT_FILE_NAME}
    else
        echo "Executing with Command Config"
        kafka-configs --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --command-config ${SCRIPT_COMMAND_CONFIG} --entity-type topics --entity-name ${topic_name} --alter --replica-placement ${SCRIPT_REPLICA_PLACEMENT_FILE_NAME}
    fi
    echo "============================================"
done
echo "============================================================================"
echo "Done"
echo "============================================================================"

echo "Do you want me to describe all the topics for sanity [y/n]?"
read SCRIPT_DESCRIBE_READ
if [[ "$SCRIPT_DESCRIBE_READ" == "y" ]] || [[ "$SCRIPT_DESCRIBE_READ" == "Y" ]] || [[ "$SCRIPT_DESCRIBE_READ" == "yes" ]] || [[ "$SCRIPT_DESCRIBE_READ" == "YES" ]]
then 
    cat ${SCRIPT_TOPIC_FILE_NAME} | while read topic_name
    do
        if [[ -z "${SCRIPT_COMMAND_CONFIG}" ]]
        then
            echo "Executing without Command Config"
            kafka-topics --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --topic ${topic_name} --describe
        else
            echo "Executing with Command Config"
            kafka-topics --bootstrap-server ${SCRIPT_BOOTSTRAP_SERVERS} --command-config ${SCRIPT_COMMAND_CONFIG} --topic ${topic_name} --describe
        fi
    echo "============================================"
    done
fi

rm ${SCRIPT_TOPIC_FILE_NAME} ${EXECUTION_TOPIC_FILE_NAME}
