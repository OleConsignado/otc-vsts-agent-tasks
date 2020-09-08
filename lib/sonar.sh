#------------------------------------------------
# Depends on assert.sh; console.sh; filesystem.sh
#------------------------------------------------

SONAR_ANALYSIS_VALIDATION_SONAR_API_STATUS_ERROR=95
SONAR_ANALYSIS_VALIDATION_SONAR_API_RESULT_ERROR=96
SONAR_ANALYSIS_VALIDATION_SONAR_API_UNKNOW_STATUS=97
SONAR_ANALYSIS_VALIDATION_MAX_POOLING_ATTEMPTS_REACHED=98
SONAR_ANALYSIS_VALIDATION_FAILED=1 # Not an error. Validation not passed

# Param pullrequest_id
# Required environment variables:
# - SONARQUBE_USERKEY
# - SONARSCANNER_END_OUTPUT_FILE
# Returns: 
#   0 - Success
#   SONAR_ANALYSIS_VALIDATION_FAILED - Not passed
#   Write report url to output 1
#   Information/Error message goes to output 2
function sonar-analysis-validation
{
	local pullrequest_id=$1

	assert-not-empty pullrequest_id
	assert-not-empty SONARQUBE_USERKEY
	assert-not-empty SONARSCANNER_END_OUTPUT_FILE

	local task_status_url=$(grep \
		'More about the report processing at ' $SONARSCANNER_END_OUTPUT_FILE | \
		egrep -o 'https?://.*')
	
	local report_url=$(grep \
		'ANALYSIS SUCCESSFUL, you can browse ' $SONARSCANNER_END_OUTPUT_FILE | \
		egrep -o 'https?://.*')
	
	local sonar_base_url=$(echo $task_status_url | sed -E 's/\/api\/ce\/task\?id=.*//g')
	local pooling_attempts=0
	
	local sonar_task_status_output_file=$(mktemp -t \
		"pr-sonar-val-status-${pullrequest_id}-XXXXXXXX.json")
	
	local sonar_task_result_output_file=$(mktemp -t \
		"pr-sonar-val-result-${pullrequest_id}-XXXXXXXX.json")
	
	local got_result=false
	local return_code=0 # Success

	while ! $got_result :
	do
		if ! curl -u $SONARQUBE_USERKEY: --fail -s $task_status_url -o "$sonar_task_status_output_file"
		then 
			red "Could not read sonar analysis status. Request to '$task_status_url' failed" >&2
			return $SONAR_ANALYSIS_VALIDATION_SONAR_API_STATUS_ERROR
		fi

		#echo "sonar-taks-status ==============================================="
		#cat $sonar_task_status_output_file
		#echo
		#echo "================================================================="

		local sonar_status=$(cat $sonar_task_status_output_file | jq -r -M '.task.status')
		local analysis_id=$(cat $sonar_task_status_output_file | jq -r -M '.task.analysisId')
		local result_url="$sonar_base_url/api/qualitygates/project_status?analysisId=$analysis_id"

		if [ "$sonar_status" != "IN_PROGRESS" ] && [ "$sonar_status" != "PENDING" ]
		then

			echo "Analysis completed!" >&2
			got_result=true

			if [ "$sonar_status" = "SUCCESS" ] 
			then					
				if ! curl -u $SONARQUBE_USERKEY: --fail -s $result_url -o $sonar_task_result_output_file
				then
					red "Could not read sonar analysis result. Request to '$result_url' failed" >&2
					return $SONAR_ANALYSIS_VALIDATION_SONAR_API_RESULT_ERROR
				fi

				#echo "sonar-result ===================================================="
				#cat $sonar_task_result_output_file
				#echo
				#echo "================================================================="

				sonar_result=$(cat $sonar_task_result_output_file | jq -r -M '.projectStatus.status')

				if [ "$sonar_result" = "OK" ]
				then
					green "Sonar analysis succeeded!" >&2
				else
					red "Sonar analysis failed! Result: $sonar_result" >&2
					return_code=$SONAR_ANALYSIS_VALIDATION_FAILED
					#echo "Sonar result:"
					#echo "--------------------------------------"
					#cat $sonar_task_result_output_file
					#echo					
				fi

				echo "$report_url" # Report url on output 1

			else
				red "Sonar analysis task provided an unknow status. Provided status: $sonar_status" >&2
				return $SONAR_ANALYSIS_VALIDATION_SONAR_API_UNKNOW_STATUS
			fi

			echo "Analysis report: $report_url" >&2

		elif [ "$pooling_attempts" -gt "60" ]
		then
			red "Too many pooling attempts, terminating." >&2
			return $SONAR_ANALYSIS_VALIDATION_MAX_POOLING_ATTEMPTS_REACHED
		fi

		rm -f $sonar_task_status_output_file > /dev/null 2>&1
			
		if ! $got_result
		then
			pooling_attempts=$((pooling_attempts+1))
			echo "Status: $sonar_status" >&2
			sleep 1
		fi
	done

	rm -f $sonar_task_result_output_file > /dev/null 2>&1

	return $return_code
}

SONAR_PR_SCANNER_BEGIN_SOURCE_DIR_NOT_FOUND=34
SONAR_PR_SCANNER_BEGIN_TEST_RESULTS_DIR_NOT_FOUND=35

# Param source_directory
# Param test_results_directory
# Required environment variables
#  - SONARQUBE_HOST
#  - SONARQUBE_USERKEY
#  - BUILD_REPOSITORY_URI
#  - BUILD_REASON
#  - If BUILD_REASON = PullRequest
#    - SYSTEM_PULLREQUEST_SOURCEBRANCH
#    - SYSTEM_PULLREQUEST_TARGETBRANCH
function sonar-scanner-begin
{
	local source_directory="$1" #"${BUILD_SOURCESDIRECTORY}/Source"
	local test_results_directory="$2" #COMMON_TESTRESULTSDIRECTORY
	assert-not-empty source_directory
	assert-not-empty test_results_directory
	directory-exists "$source_directory" || return $SONAR_PR_SCANNER_BEGIN_SOURCE_DIR_NOT_FOUND
	directory-exists "$test_results_directory" || return $SONAR_PR_SCANNER_BEGIN_TEST_RESULTS_DIR_NOT_FOUND
	assert-not-empty BUILD_REASON
	assert-not-empty SONARQUBE_HOST
	assert-not-empty SONARQUBE_USERKEY
	assert-not-empty BUILD_REPOSITORY_URI
	
	local is_pullrequest=false

	if [ "$BUILD_REASON" = "PullRequest" ]
	then
		is_pullrequest=true
	fi

	local sonar_projectkey=$(find "$source_directory" -name *.sln | egrep -o '[^/]+.sln$' | sed s/\.sln//)
	local coverage_exclusions="**/*Exception.cs"
	
	for i in $(find "$source_directory" -name *.csproj); 
	do 
		if grep -Pzlv "<DebugType *>[\r\n\t ]*Full[\r\n\t ]*</DebugType>" $i > /dev/null 2>&1 
		then 
			coverage_exclusions="$coverage_exclusions,**/$(basename $(dirname $i))/**/*"
		fi 
	done

	local duplicated_exclusions="**/*Adapter/Clients/**/*Post.cs,**/*Adapter/Clients/**/*Get.cs,\
**/*Adapter/Clients/**/*Put.cs,**/*Adapter/Clients/**/*Patch.cs,\
**/*Adapter/Clients/**/*Delete.cs,**/*Adapter/Clients/**/*PostResult.cs,\
**/*Adapter/Clients/**/*GetResult.cs,**/*Adapter/Clients/**/*PutResult.cs,\
**/*Adapter/Clients/**/*PatchResult.cs,**/*Adapter/Clients/**/*DeleteResult.cs,\
**/*Adapter/Clients/**/*Dto.cs,**/*Adapter/Clients/*Post.cs,\
**/*Adapter/Clients/*Get.cs,**/*Adapter/Clients/*Put.cs,**/*Adapter/Clients/*Patch.cs,\
**/*Adapter/Clients/*Delete.cs,**/*Adapter/Clients/*PostResult.cs,\
**/*Adapter/Clients/*GetResult.cs,**/*Adapter/Clients/*PutResult.cs,\
**/*Adapter/Clients/*PatchResult.cs,**/*Adapter/Clients/*DeleteResult.cs,\
**/*Adapter/Clients/*Dto.cs,**/*.WebApi/Dtos/**/*Post.cs,**/*.WebApi/Dtos/**/*Get.cs,\
**/*.WebApi/Dtos/**/*Put.cs,**/*.WebApi/Dtos/**/*Patch.cs,\
**/*.WebApi/Dtos/**/*Delete.cs,**/*.WebApi/Dtos/**/*PostResult.cs,\
**/*.WebApi/Dtos/**/*GetResult.cs,**/*.WebApi/Dtos/**/*PutResult.cs,\
**/*.WebApi/Dtos/**/*PatchResult.cs,**/*.WebApi/Dtos/**/*DeleteResult.cs,\
**/*.WebApi/Dtos/**/*Dto.cs,**/*.WebApi/Dtos/*Post.cs,**/*.WebApi/Dtos/*Get.cs,\
**/*.WebApi/Dtos/*Put.cs,**/*.WebApi/Dtos/*Patch.cs,**/*.WebApi/Dtos/*Delete.cs,\
**/*.WebApi/Dtos/*PostResult.cs,**/*.WebApi/Dtos/*GetResult.cs,\
**/*.WebApi/Dtos/*PutResult.cs,**/*.WebApi/Dtos/*PatchResult.cs,\
**/*.WebApi/Dtos/*DeleteResult.cs,**/*.WebApi/Dtos/*Dto.cs"

	local sonarscanner_begin_args="/key:$sonar_projectkey /d:sonar.host.url=$SONARQUBE_HOST \
	/d:sonar.cs.opencover.reportsPaths=$test_results_directory/*.opencover.xml \
	/d:sonar.login=$SONARQUBE_USERKEY \
	/d:sonar.links.scm=$BUILD_REPOSITORY_URI \
	/d:sonar.links.homepage=$BUILD_REPOSITORY_URI \
	/d:sonar.coverage.exclusions=$coverage_exclusions \
	/d:sonar.cpd.exclusions=$duplicated_exclusions \
	/v:1"

	if $is_pullrequest
	then
		assert-not-empty SYSTEM_PULLREQUEST_SOURCEBRANCH
		assert-not-empty SYSTEM_PULLREQUEST_TARGETBRANCH
		local pullrequest_branch=$(echo $SYSTEM_PULLREQUEST_SOURCEBRANCH | sed 's/^refs\/heads\///')
		local pullrequest_base=$(echo $SYSTEM_PULLREQUEST_TARGETBRANCH | sed 's/^refs\/heads\///')
		sonarscanner_begin_args="$sonarscanner_begin_args \
				/d:sonar.branch.target=$pullrequest_base \
				/d:sonar.branch.name=$pullrequest_branch"
	fi

	export MSYS2_ARG_CONV_EXCL="*"
	assert-success dotnet sonarscanner begin $sonarscanner_begin_args
	unset MSYS2_ARG_CONV_EXCL
}
