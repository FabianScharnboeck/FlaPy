#!/usr/bin/env bash

SCRIPT_DIR=$(dirname $0)

source "$SCRIPT_DIR/utils.sh"

# -- DOC
# This scripts require LOCAL_PODMAN_ROOT to be set

# -- CHECK NUMBER OF ARGUMENTS
if [[ "$#" -lt 5 ]]; then
    debug_echo "Usage: ./flapy.sh run RUN_ON  CONSTRAINT  INPUT_CSV  PLUS_RANDOM_RUNS  FLAPY_ARGS  [OUT_DIR]

    RUN_ON must be either 'locally' or 'cluster'
    CONSTRAINT is the \`sbatch --constraint\` in case RUN_ON == 'cluster'
    INPUT_CSV is the flapy input csv file,
        which must have the following columns in the following order:
        PROJECT_NAME, PROJECT_URL, PROJECT_HASH, PYPI_TAG, FUNCS_TO_TRACE, TESTS_TO_RUN, NUM_RUNS
    PLUS_RANDOM_RUNS must be 'true' or 'false'
    FLAPY_ARGS can contain the following, but must always be provided, even as empty string.
        Must always be one string.
        Available options:
        --random-order-seed <seed>
    OUT_DIR is the parent folder of the output results directory.
        If this option is not provided, the current directory is used

Example (takes ~30min): ./flapy.sh run locally \"\" flapy_input_example.csv false \"\" example_results

Example (takes ~30s): ./flapy.sh run locally \"\" flapy_input_example_tiny.csv false \"\" example_results_tiny
"
    exit 1
fi

# TODO: use getopts
# SHORT="r,c:,a:"
# LONG="plus-random-runs,constraint:,additional-args:"
#
# OPTS=$(getopts --options $SHORT --longoptions $LONG)
#
# echo $OPTS


# -- PARSE ARGUMENTS
RUN_ON=$1
CONSTRAINT=$2
CSV_FILE=$3
PLUS_RANDOM_RUNS=$4
FLAPY_ARGS=$5
RESULTS_PARENT_FOLDER=$6

# -- DEBUG OUTPUT
debug_echo "-- $0"
debug_echo "    Run on:                $RUN_ON"
debug_echo "    Constraint:            $CONSTRAINT"
debug_echo "    CSV file:              $CSV_FILE"
debug_echo "    Plus random runs:      $PLUS_RANDOM_RUNS"
debug_echo "    Flapy args:            $FLAPY_ARGS"
debug_echo "    Results parent folder: $RESULTS_PARENT_FOLDER"
debug_echo "    ----"

# -- INPUT PRE-PROCESSING
dos2unix "${CSV_FILE}"
CSV_FILE_LENGTH=$(wc -l < "$CSV_FILE")
debug_echo "    CSV file length:   $CSV_FILE_LENGTH"

# -- CREATE RESULTS_DIR
if [ -z "${RESULTS_PARENT_FOLDER}" ]; then
    RESULTS_PARENT_FOLDER=$(pwd)
else
    RESULTS_PARENT_FOLDER=$(realpath "$RESULTS_PARENT_FOLDER")
fi
DATE_TIME=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="${RESULTS_PARENT_FOLDER}/flapy-results_${DATE_TIME}"
mkdir -p "${RESULTS_DIR}"

# -- SAVE INPUT FILE
FLAPY_META_FOLDER="$RESULTS_DIR/!flapy.run/"
mkdir "${FLAPY_META_FOLDER}"
cp "${CSV_FILE}" "${FLAPY_META_FOLDER}/input.csv"

# -- LOG META INFOS
FLAPY_META_FILE="$FLAPY_META_FOLDER/flapy_run.yaml"
{
    echo "run_on:                 \"$RUN_ON\""
    echo "constraint:             \"$CONSTRAINT\""
    echo "csv_file:               \"$CSV_FILE\""
    echo "plus_random_runs:       \"$PLUS_RANDOM_RUNS\""
    echo "flapy_args:             \"$FLAPY_ARGS\""
    echo "csv_file_length:        $CSV_FILE_LENGTH"
} >> "$FLAPY_META_FILE"


# -- EXPORT VARIABLE
#     these variables will be picked up by run_line.sh
export FLAPY_INPUT_CSV_FILE="${FLAPY_META_FOLDER}/input.csv"
export FLAPY_INPUT_PLUS_RANDOM_RUNS=$PLUS_RANDOM_RUNS
export FLAPY_INPUT_OTHER_ARGS=$FLAPY_ARGS
export FLAPY_INPUT_RUN_ON=$RUN_ON
export FLAPY_DATE_TIME=$DATE_TIME
export FLAPY_RESULTS_DIR=$RESULTS_DIR

# -- SBATCH LOG FILES
SBATCH_LOG_FOLDER="$FLAPY_META_FOLDER/sbatch_logs/"
mkdir -p "$SBATCH_LOG_FOLDER"
SBATCH_LOG_FILE_PATTERN="$SBATCH_LOG_FOLDER/log-%a.out"

# -- RUN
if [[ $RUN_ON = "cluster" ]]
then
    debug_echo "running on cluster"
    # export PODMAN_HOME=
    # export LOCAL_PODMAN_ROOT=
    sbatch_info=$(sbatch --parsable \
        --constraint="$CONSTRAINT" \
        --output "$SBATCH_LOG_FILE_PATTERN" \
        --error  "$SBATCH_LOG_FILE_PATTERN" \
        --array=2-"$CSV_FILE_LENGTH" \
        -- \
        run_line.sh
    )
    debug_echo "sbatch_submission_info: $sbatch_info"
    echo "sbatch_submission_info: \"$sbatch_info\"" >> "$FLAPY_META_FILE"
elif [[ $RUN_ON = "locally" ]]
then
    for i in $(seq 2 "$CSV_FILE_LENGTH"); do
        FLAPY_INPUT_CSV_LINE_NUM=$i "$SCRIPT_DIR/run_line.sh"
    done
else
    debug_echo "Unknown value '$RUN_ON' for RUN_ON. Please use 'cluster' or 'locally'."
    exit
fi

