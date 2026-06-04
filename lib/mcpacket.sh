#!/bin/bash

run_pipeline() {
    local pipeline_name="$1"
    shift || true

    load_config "$pipeline_name"
    load_pipeline_config "$pipeline_name"

    local pipeline_file="$PIPELINES_DIR/$pipeline_name.pipeline.sh"
    [[ -f "$pipeline_file" ]] || {
        log_error "Pipeline not found: $pipeline_file"
        return 1
    }

    PIPELINE_STEPS=()
    PIPELINE_INPUT=""
    PIPELINE_OUTPUT=""

    # shellcheck source=/dev/null
    source "$pipeline_file"

    local step_count="${#PIPELINE_STEPS[@]}"
    # [[ "${#PIPELINE_STEPS[@]}" -gt 0 ]] || {
    [[ "$step_count" -gt 0 ]] || {
        log_error "Pipeline has no steps: $pipeline_name"
        return 1
    }
    [[ -n "$PIPELINE_INPUT" ]] || {
        log_error "Pipeline input is empty: $pipeline_name"
        return 1
    }

    local pipeline_run_dir="$TEMP_RUN_DIR/pipelines/$pipeline_name/$RUN_ID"
    mkdir -p "$pipeline_run_dir"
    register_cleanup_dir "$pipeline_run_dir"

    log_info "Pipeline started: $pipeline_name"
    log_info "Pipeline input: $PIPELINE_INPUT"

    local input_file="$PIPELINE_INPUT"
    local output_file step index
    index=0

    for step in "${PIPELINE_STEPS[@]}"; do
        index=$((index + 1))

        # if [[ "$index" -eq "${#PIPELINE_STEPS[@]}" && -n "$PIPELINE_OUTPUT" ]]; then
        if [[ "$index" -eq "$step_count" && -n "$PIPELINE_OUTPUT" ]]; then    
    	    output_file="$PIPELINE_OUTPUT"
        else
            output_file="$pipeline_run_dir/${index}_${step}.out"
        fi

        # log_info "Pipeline step $index/${#PIPELINE_STEPS[@]}: $step"
	log_info "Pipeline step $index/$step_count: $step"
        run_module_step "$step" "$input_file" "$output_file"
        input_file="$output_file"
    done

    log_success "Pipeline completed: $pipeline_name"
    log_success "Pipeline output: $input_file"
}
