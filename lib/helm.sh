#------------------------------------------------
# Depends on filesystem.sh; assert.sh; console.sh
#------------------------------------------------

# discover-chart-name 
# Get chart name for the given helm chart directory.

DISCOVER_DISCOVER_CHART_NAME_ERROR_HELM_DIR=4
DISCOVER_CHART_NAME_ERROR=5

# Param helm_dir
# Return chart_name
function discover-chart-name 
{
	local helm_dir=$1
	directory-exists "$helm_dir" || return $DISCOVER_DISCOVER_CHART_NAME_ERROR_HELM_DIR
	local chart_yaml_filename="$helm_dir/Chart.yaml"
	local chart_name=$(egrep '^name: ' "$chart_yaml_filename" | awk '{ print $2 }')	
	if [ -z "$chart_name" ]
	then
		echo "discover-chart-name : Could not find the chartname, check file '$chart_yaml_filename'." >&2
		return $DISCOVER_CHART_NAME_ERROR
	fi
	echo $chart_name
}

# edit-helm-tag
# Usage: edit-helm-tag helm_dir new_tag

EDIT_HELM_TAG_HELM_DIR_NOT_FOUND=88
EDIT_HELM_TAG_VALUES_NOT_FOUND=89

# Param helm_dir
# Param tag
function edit-helm-tag
{
	local helm_dir=$1
	local tag=$2
	directory-exists "$helm_dir" || return $EDIT_HELM_TAG_HELM_DIR_NOT_FOUND
	assert-not-empty tag
	local values_path="$helm_dir/values.yaml"
	if ! [ -f "$values_path" ]
	then
		echo "edit-helm-tag: File '$values_path' not found." >&2
		return $EDIT_HELM_TAG_VALUES_NOT_FOUND
	fi
	sed -ri "s/^  tag: .*/  tag: $tag/" "$values_path"
	git add "$values_path"
}

# helm-dry-run
# Usage: helm-dry-run helm_dir

HELM_DRY_RUN_FAILED=45
HELM_DRY_RUN_HELM_DIR_NOT_FOUND=46

# Param helm_dir
function helm-dry-run
{
	local helm_dir="$1"
	directory-exists "$helm_dir" || return $HELM_DRY_RUN_HELM_DIR_NOT_FOUND
	echo -n "Performing helm dry-run... " >&2
	if ! helm install "$helm_dir" --dry-run > /dev/null 2>&1
	then
		red "FAILED!" >&2
		echo "helm-dry-run: helm dry-run failed, performing helm dry-run with --debug in order to expose errors." >&2
		! helm install "$helm_dir" --dry-run --debug
		return $HELM_DRY_RUN_FAILED
	fi
	green "Passed!" >&2
}

# helm-release-exists
# Usage: helm-release-exists namespace helm_release_name

HELM_RELEASE_EXISTS_NOT_EXISTS=60

# Param namespace
# Param helm_release_name
function helm-release-exists
{
	local namespace=$1
	local helm_release_name=$2
	assert-not-empty namespace
	assert-not-empty helm_release_name
	if ! helm --namespace="$namespace" ls -q | egrep "^$helm_release_name\$" > /dev/null
	then
		return $HELM_RELEASE_EXISTS_NOT_EXISTS
	fi
}

# helm-install-or-upgrade
# Usage: helm-install-or-upgrade helm_dir namespace helm_release_name item1=va1 item2=val2 ....

HELM_INSTALL_OR_UPGRADE_INVALID_CUSTOM_VALUE=55
HELM_INSTALL_OR_UPGRADE_INST_FAILED=58
HELM_INSTALL_OR_UPGRADE_HELM_DIR_NOT_FOUND=59
HELM_INSTALL_OR_UPGRADE_UPGR_FAILED=60

# Param helm_dir
# Param namespace
# Param helm_release_name
# Param helm_values - ex: item1=val1 item2=val2
function helm-install-or-upgrade
{
	local helm_dir=$1
	local namespace=$2
	local helm_release_name=$3
	shift 3
	local helm_custom_values=$@
	directory-exists "$helm_dir" || return $HELM_INSTALL_OR_UPGRADE_HELM_DIR_NOT_FOUND
	assert-not-empty namespace
	assert-not-empty helm_release_name
	local helm_set_arg=''
	for item in $helm_custom_values
	do 
		if ! echo "$item" | egrep '^[a-zA-Z_0-9-]+=[a-zA-Z_0-9-]+$' > /dev/null
		then
			echo "helm-install-or-upgrade: Argument '$item' is invalid for helm_custom_values" >&2
			return $HELM_INSTALL_OR_UPGRADE_INVALID_CUSTOM_VALUE
		fi
		helm_set_arg="$helm_set_arg --set $item"
	done

	if helm-release-exists "$namespace" "$helm_release_name"
	then
	    # Release already exists, will upgrade
	    echo "Upgrading helm $helm_release_name ..."
	    if ! helm --namespace="$namespace" upgrade "$helm_release_name" $helm_set_arg "$helm_dir"
	    then
	    	echo "helm-install-or-upgrade: helm upgrade failed." >&2
	    	return $HELM_INSTALL_OR_UPGRADE_UPGR_FAILED
	    fi
	else
		# New release
		echo "Installing helm $helm_release_name ..."
		if ! helm --namespace="$namespace" install --name="$helm_release_name" $helm_set_arg "$helm_dir"
		then
			echo "helm-install-or-upgrade: helm install failed." >&2
			# Delete release only if is a new release
			helm delete "$helm_release_name" --purge
			return $HELM_INSTALL_OR_UPGRADE_INST_FAILED
		fi		
	fi
}

# helm-deploy-validation
# Usage: helm-deploy-validation namespace helm_release_name

HELM_DEPLOY_VALIDATION_REVISION_NOT_FOUND=79
HELM_DEPLOY_VALIDATION_POD_CREATION_FAIL=80
HELM_DEPLOY_VALIDATION_POD_START_FAIL=81

# Param namespace
# Param helm_release_name
function helm-deploy-validation
{
	local namespace="$1"
	local helm_release_name="$2"
	assert-not-empty namespace
	assert-not-empty helm_release_name

	local release_revision=$(helm get "$helm_release_name" | head -1 | grep ^REVISION: | awk '{ print $2 }')

	if ! echo $release_revision | egrep '^[1-9][0-9]*$' > /dev/null 2>&1
	then
		echo "Could not get helm release revision." >&2
		return $HELM_DEPLOY_VALIDATION_REVISION_NOT_FOUND
	fi	

	echo -n "Checking POD creation... " >&2
	local pooling_attemps=0
	local kubectl_labels_args="-l release=$helm_release_name,revision=$release_revision";
	local kubectl_get_pod_cmd="kubectl -n $namespace get pod $kubectl_labels_args -ojson"

	while : 
		[ "$($kubectl_get_pod_cmd | jq -M '.items[0]')" = "null" ]
	do
		# POD creation should not exceeds 30 seconds.
		# If it exceeds, must be something wrong on Kubernetes scheduling
		if [ "$pooling_attemps" -gt 30 ]
		then
			echo "FAILED" >&2
			echo "Could not validate POD creation." >&2
			return $HELM_DEPLOY_VALIDATION_POD_CREATION_FAIL
		fi

		echo -n '.' >&2
		sleep 1
		pooling_attemps=$((pooling_attemps+1))
	done

	echo "OK" >&2

	# check POD status

	echo "Checking POD status." >&2

	pooling_attemps=0
	local max_pooling_attemps=180
	local deploy_validation_completed=false
	local deploy_sucess=false
	local pod_status_pending=false	
	local prev_pooling_attemps_step=""

	while : 
		[ "$pooling_attemps" -lt "$max_pooling_attemps" ] && ! $deploy_validation_completed
	do
		local pooling_attemps_step=""
		local pod_ready=""
		local reason=""
		local pod_status=$($kubectl_get_pod_cmd | jq -M '.items[0]?.status')
		local container_status=$(echo $pod_status | jq -M '.containerStatuses[0]?.state')

		if [ "$container_status" = "null" ] && [ "$(echo $pod_status | jq -Mr '.phase')" = "Pending" ]
		then
			pod_status_pending=true
			pooling_attemps_step="PENDING"
			echo "Pending..." >&2
		else
			pod_status_pending=false

			if [ "$container_status" = "null" ]
			then
				pooling_attemps_step="INITIAL"
				echo "Waiting..." >&2
			elif [ "$(echo $container_status | jq -M '.waiting')" != "null" ]
			then
				pooling_attemps_step="CONTAINER_CREATING"

				reason=$(echo $container_status | jq -Mr '.waiting.reason')

				if [ "$reason" = "ImagePullBackOff" ] || [ "$reason" = "ErrImagePull" ]
				then
					red "Deployment status is $reason, this means that docker failed while pulling the image. " >&2
					red "Probably the image does not exists or appropriate registry's credentials is missing." >&2
					deploy_validation_completed=true
					deploy_sucess=false
				else
					echo "Waiting: $reason" >&2

					if [ "$reason" = "CrashLoopBackOff" ]
					then
						deploy_validation_completed=true
						deploy_sucess=false
					fi

				fi
			elif [ "$(echo $container_status | jq -M '.running')" != "null" ] 
			then
				#echo $container_status | jq -M '.running'
				pooling_attemps_step="CHECK_READYNESS"
				pod_ready=$(echo $pod_status | jq -Mr '.conditions[] | select(.type == "Ready") | .status')

				if [ "$pod_ready" = "True" ]
				then
					deploy_validation_completed=true
					deploy_sucess=true
				else
					echo "Container running... Looking for ready status [$pod_ready]" >&2
				fi

			elif [ "$(echo $container_status | jq -M '.terminated')" != "null" ] 
			then
				reason=$(echo $container_status | jq -Mr '.terminated.reason')
				echo "Terminated: $reason" >&2 # reason: Error

				deploy_validation_completed=true
				deploy_sucess=false
			else
				echo "## STATUS NOT MAPPED ##################################################" >&2
				echo $container_status >&2
			fi
		fi

		if [ "$prev_pooling_attemps_step" != "$pooling_attemps_step" ]
		then
			pooling_attemps=0
		fi

		prev_pooling_attemps_step=$pooling_attemps_step

		sleep 1
		pooling_attemps=$((pooling_attemps+1))
	done

	if ! $deploy_sucess
	then
		local kubectl_describe_pod_cmd="kubectl -n $namespace describe pod $kubectl_labels_args"
		if $pod_status_pending
		then
			red "Error while trying to start $helm_release_name." >&2
			echo "POD pending: Kubernetes low on resources." >&2
		elif ! $deploy_validation_completed
		then
			red "Could not validate deployment, the POD is taking a long time to get ready, should be something wrong on Kubernetes Cluster." >&2
			bgred "==== POD details (kubectl describe pod):" >&2
			$kubectl_describe_pod_cmd >&2
			bgred "==== End of POD details" >&2
		else
			# TODO: improve log
			red "Error while trying to start $helm_release_name" >&2
			local kubectl_logs_cmd="kubectl -n $namespace logs $kubectl_labels_args"
			bgred "==== Current POD logs (kubectl logs):" >&2
			if ! $kubectl_logs_cmd >&2
			then
				yellow "Could not get current POD logs." >&2
			fi
			bgred "==== End of current POD logs; Previous POD logs (kubectl logs -p):" >&2
			if ! $kubectl_logs_cmd -p >&2
			then
				yellow "Could not get previous POD logs." >&2
			fi			
			bgred "==== End of previous POD logs; POD details (kubectl describe pod):" >&2
			if ! $kubectl_describe_pod_cmd >&2
			then
				red "Could not describe POD." >&2
			fi
			bgred "==== End of POD details" >&2
		fi
		echo >&2
		red "$helm_release_name not deployed." >&2

		return $HELM_DEPLOY_VALIDATION_POD_START_FAIL
	fi

	echo >&2
	green "$helm_release_name successfuly deployed." >&2
}

# helm-deploy
# Perform install-or-upgrade then deploy validation

HELM_DEPLOY_HELM_DIR_NOT_FOUND=9
HELM_DEPLOY_DRY_RUN_FAILED=11
HELM_DEPLOY_INSTALL_OR_UPGRADE_FAILED=12
HELM_DEPLOY_VALIDATION_FAILED=13
HELM_GENERAL_DEPLOY_ERROR_MESSAGE='This is not a regular error. If you reading this message, 
helm/kubernetes apiserver could became unvailable or there is a BUG in this script.'
# Param helm_dir - Helm chart directory
# Param namespace
# Param custom_name (optional) - artifact name, applyed to release name and values.Name
# Output 1 - release_name's
function helm-deploy
{
	local helm_dir="$1"
	local namespace="$2"
	local custom_name="$3"

	assert-not-empty helm_dir
	assert-not-empty namespace

	directory-exists "$helm_dir" || return $HELM_DEPLOY_HELM_DIR_NOT_FOUND

	local chart_name="$custom_name"

	if [ -z "$chart_name" ]
	then
		chart_name=$(discover-chart-name "$helm_dir")
	fi
	
	local return_code=0

	if ! helm-dry-run "$helm_dir" >&2
	then
		return $HELM_DEPLOY_DRY_RUN_FAILED
	fi

	local release_name="r-${chart_name}-${namespace}"

	if ! helm-install-or-upgrade "$helm_dir" "$namespace" \
		"$release_name" "Name=$chart_name" >&2
	then
		return_code=$HELM_DEPLOY_INSTALL_OR_UPGRADE_FAILED
	elif ! helm-deploy-validation "$namespace" "$release_name" >&2 # Validation
	then
		return_code=$HELM_DEPLOY_VALIDATION_FAILED
	fi

	echo $release_name

	return $return_code
}
