#!/bin/bash

module_init() {
    local input_file="$1"
        local output_file="$2"
        
    check_dependencies awk cat date grep sort ssh timeout
                    
        [[ -f "$input_file" ]] || {
        log_error "Mcpacket device list not found: $input_file"
        return 1
    }
                    
        : "${MCPACKET_REMOTE_DATA_BASE:?MCPACKET_REMOTE_DATA_BASE is required}"
    : "${MCPACKET_TARGET_DATE:?MCPACKET_TARGET_DATE is required}"
        : "${MCPACKET_TARGET_TIME:?MCPACKET_TARGET_TIME is required}"
    : "${MCPACKET_FILTER_KEY0:?MCPACKET_FILTER_KEY0 is required}"
        : "${MCPACKET_FILTER_KEY1:?MCPACKET_FILTER_KEY1 is required}"
    : "${MCPACKET_FILTER_KEY2:?MCPACKET_FILTER_KEY2 is required}"
        : "${MCPACKET_FILTER_KEY3:?MCPACKET_FILTER_KEY3 is required}"
    : "${MCPACKET_FILE_GLOB:?MCPACKET_FILE_GLOB is required}"
        : "${MCPACKET_MAX_PARALLEL:?MCPACKET_MAX_PARALLEL is required}"
    : "${MCPACKET_SSH_OPTS:?MCPACKET_SSH_OPTS is required}"
                    
        MCPACKET_TOTAL_OUTPUT_FILE="${MCPACKET_TOTAL_OUTPUT_FILE:-$RESULT_BASE_DIR/mcpacket/all_devices_summary_${MCPACKET_TARGET_DATE}.csv}"
    export MCPACKET_TOTAL_OUTPUT_FILE
                    
        mkdir -p "$MODULE_TMP_RUN_DIR/device_out" "$(dirname "$output_file")" "$(dirname "$MCPACKET_TOTAL_OUTPUT_FILE")"
}

_mcpacket_worker() {
    local device="$1"
        local target_date="$2"
    local slot="$3"
        local safe_device result rc rx_cnt exp_cnt lost_cnt date_path slot_path
    
    safe_device="${device//[^A-Za-z0-9_.-]/_}"
        date_path="${MCPACKET_REMOTE_DATA_BASE%/}/${target_date}"
    slot_path="${date_path}/${slot}"
                    
        local attempt=1
    local max_attempts=4  
        local wait_sec=2      
    local success=0

        while [[ "$attempt" -le "$max_attempts" ]]; do
        set +e
        result="$(
            timeout 45s ssh ${MCPACKET_SSH_OPTS//-n/} "$device" "
                    set +e; set +u;
                    if [ -d \"${slot_path}\" ]; then
                         files=\$(find \"${slot_path}\" -maxdepth 1 -type f -name \"${MCPACKET_FILE_GLOB}*\" 2>/dev/null);
                      if [ -n \"\$files\" ]; then
                               echo \"\$files\" | xargs zcat -f 2>/dev/null | awk -v k0=\"${MCPACKET_FILTER_KEY0}\" -v k1=\"${MCPACKET_FILTER_KEY1}\" -v k2=\"${MCPACKET_FILTER_KEY2}\" -v k3=\"${MCPACKET_FILTER_KEY3}\" '
                                   BEGIN { rx_sum=0; exp_sum=0; lost_sum=0 }
                               {
                                       if (index(\$0, k0) > 0) {
                                           if (index(\$0, k1) > 0) {
                                           s1 = \$0; sub(\".*\" k1, \"\", s1); 
                                           gsub(/^[^0-9]+/, \"\", s1); match(s1, /^[0-9]+/);
                                           if (RLENGTH > 0) rx_sum += substr(s1, RSTART, RLENGTH);
                                       }
                                           if (index(\$0, k2) > 0) {
                                           s2 = \$0; sub(\".*\" k2, \"\", s2); 
                                           gsub(/^[^0-9]+/, \"\", s2); match(s2, /^[0-9]+/);
                                           if (RLENGTH > 0) exp_sum += substr(s2, RSTART, RLENGTH);
                                       }
                                           if (index(\$0, k3) > 0) {
                                           s3 = \$0; sub(\".*\" k3, \"\", s3); 
                                           gsub(/^[^0-9]+/, \"\", s3); match(s3, /^[0-9]+/);
                                           if (RLENGTH > 0) lost_sum += substr(s3, RSTART, RLENGTH);
                                       }
                                       }
                                   }
                               END { print rx_sum+0, exp_sum+0, lost_sum+0 }
                                ' 2>/dev/null;
                     else
                              echo \"0 0 0\";
                           fi
                   else
                        echo \"0 0 0\";
                fi
            " < /dev/null
            )"
            rc=$?
            set -e

            if [[ "$rc" -eq 0 ]] && [[ -n "$result" ]]; then
                success=1
            break
            fi
            if [[ "$rc" -eq 124 ]]; then
                local fault_msg="Job timeout (45s)"
            else
                local fault_msg="Job failed with rc=$rc"
            fi

            if [[ "$attempt" -eq 1 ]]; then
                log_warn "$fault_msg on $device $slot [Initial Attempt Failed]"
            else
                log_warn "$fault_msg on $device $slot [Retry $((attempt-1))/3]"
            fi

            attempt=$((attempt + 1))
        done

    if [[ "$success" -eq 1 ]]; then
            read -r rx_cnt exp_cnt lost_cnt <<< "$(echo "$result" | tail -n 1)"
            rx_cnt="${rx_cnt:-0}"
            exp_cnt="${exp_cnt:-0}"
            lost_cnt="${lost_cnt:-0}"
        else
        rx_cnt=0; exp_cnt=0; lost_cnt=0
        log_error "Mcpacket collection completely failed after 3 retries: $device $slot"
    fi
                    
        echo "${target_date},${device},${slot},${rx_cnt},${exp_cnt},${lost_cnt}" > "$MODULE_TMP_RUN_DIR/device_out/${safe_device}_${slot}.data"
}

_mcpacket_write_totals() {
    local detail_file="$1"
    local total_file="$2"
    local target_date="$3"
    local time_slots_csv="$4"
    local slot t_rx t_exp t_lost loss_rate raw_loss_rate
    local -a time_slots=()
                
    local OLD_IFS="$IFS"
    IFS=',' read -r -a time_slots <<< "$time_slots_csv"
    IFS="$OLD_IFS"
            
    echo "Date,TimeSlot,Total_PacketsReceived,Total_PacketsExpected,Total_PacketsLost,PacketLossRate" > "$total_file"
                
    for slot in "${time_slots[@]}"; do
        [[ -z "$slot" ]] && continue
        read -r t_rx t_exp t_lost <<< "$(awk -F',' -v slot="$slot" '
            $3 == slot { rx += $4; expected += $5; lost += $6; found=1 }
            END { if(found) print rx+0, expected+0, lost+0; else print "0 0 0" }
        ' "$detail_file")"
                 
        t_rx="${t_rx:-0}"
        t_exp="${t_exp:-0}"
        t_lost="${t_lost:-0}"
                    
        if [[ "$t_exp" -gt 0 ]]; then
            loss_rate="$(awk -v lost="$t_lost" -v expected="$t_exp" 'BEGIN { printf "%.4f%%", (lost/expected)*100 }')"
            raw_loss_rate="$(awk -v lost="$t_lost" -v expected="$t_exp" 'BEGIN { printf "%.4f", (lost/expected)*100 }')"
        else
            loss_rate="0.0000%"
            raw_loss_rate="0.0000"
        fi
                       
        echo "${target_date},${slot},${t_rx},${t_exp},${t_lost},${loss_rate}" >> "$total_file"

        local breach_check
        breach_check="$(awk -v current="$raw_loss_rate" -v threshold="$MCPACKET_LOSS_THRESHOLD" 'BEGIN { print (current > threshold) ? 1 : 0 }')"
           
        if [[ "$breach_check" -eq 1 ]]; then
            log_error "ALERT: Packet loss rate ($loss_rate) in Slot $slot [$device] breached the configured threshold (${MCPACKET_LOSS_THRESHOLD}%)!"
        fi
   done
}

module_run() {
     local input_file="$1"
     local output_file="$2"
                     
     echo "Date,Device,TimeSlot,PacketsReceived,PacketsExpected,PacketsLost" > "$output_file"
         
     local device slot
     local -a time_slots=()
     declare -A seen_devices=()
                     
     local OLD_IFS="$IFS"
     IFS=',' read -r -a time_slots <<< "$MCPACKET_TARGET_TIME"
     IFS="$OLD_IFS"
         
     log_info "Starting mcpacket collection (Atomic Flow-Controlled Parallel Mode)"
                     
     local max_p="${MCPACKET_MAX_PARALLEL:-20}"
     local job_count=0

     while IFS= read -r device || [[ -n "$device" ]]; do
          [[ -z "$device" || "$device" =~ ^# ]] && continue
                
          if [[ -n "${seen_devices[$device]:-}" ]]; then
                 continue
          fi
          seen_devices["$device"]=1
                          
          for slot in "${time_slots[@]}"; do
              [[ -z "$slot" ]] && continue
                          
              _mcpacket_worker "$device" "$MCPACKET_TARGET_DATE" "$slot" &
              
              job_count=$((job_count + 1))
              if [[ "$job_count" -ge "$max_p" ]]; then
                   wait -n 2>/dev/null || wait || true
                   job_count=$((job_count - 1))
              fi
              sleep 0.05
           done
     done < "$input_file"
                 
     log_info "All background sync tasks submitted successfully, waiting for remaining data to land..."
     wait || true
                 
     shopt -s nullglob
     cat "$MODULE_TMP_RUN_DIR"/device_out/*.data 2>/dev/null | sort -t',' -k1,1 -k2,2 -k3,3 >> "$output_file"
     shopt -u nullglob
             
     _mcpacket_write_totals "$output_file" "$MCPACKET_TOTAL_OUTPUT_FILE" "$MCPACKET_TARGET_DATE" "$MCPACKET_TARGET_TIME"
     log_success "Mcpacket device report: $output_file"
     log_success "Mcpacket total report: $MCPACKET_TOTAL_OUTPUT_FILE"
 }

module_cleanup() {
     safe_rm_dir "$MODULE_TMP_RUN_DIR" 2>/dev/null || true
}

