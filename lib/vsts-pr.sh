#------------------------------
# Depends on assert.sh; vsts.sh
#------------------------------

# Param pullrequest_id
# Param pr_size_data_json, schema example:
# {
#   "filtered": {
#     "insertions": 20,
#     "deletions": 16,
#     "comments_or_blank_lines": 4
#   },
#   "raw": {
#     "insertions": 28,
#     "deletions": 23,
#     "comments_or_blank_lines": 4
#   }
# }
function pullrequest-update-properties
{
	local pullrequest_id="$1"
	local pr_size_data_json="$2"
	assert-not-empty pr_size_data_json
	assert-not-empty pullrequest_id
	local payload=$(echo $pr_size_data_json | jq -M '[
		{ 
			"op": "replace", 
			"path": "/Otc.PRAnalytics.PRSize.Filtered.Insertions", 
			"from": null, 
			"value": .filtered.insertions  
		},
		{ 
			"op": "replace", 
			"path": "/Otc.PRAnalytics.PRSize.Filtered.Deletions", 
			"from": null, 
			"value": .filtered.deletions
		},
		{ 
			"op": "replace", 
			"path": "/Otc.PRAnalytics.PRSize.Filtered.CommentsOrBlankLines", 
			"from": null, 
			"value": .filtered.comments_or_blank_lines
		},
		{ 
			"op": "replace", 
			"path": "/Otc.PRAnalytics.PRSize.Raw.Insertions", 
			"from": null, 
			"value": .raw.insertions  
		},
		{ 
			"op": "replace", 
			"path": "/Otc.PRAnalytics.PRSize.Raw.Deletions", 
			"from": null, 
			"value": .raw.deletions
		},
		{ 
			"op": "replace", 
			"path": "/Otc.PRAnalytics.PRSize.Raw.CommentsOrBlankLines", 
			"from": null, 
			"value": .raw.comments_or_blank_lines
		}		
	]')

	vsts-pr-update-properties "$pullrequest_id" "$payload"
}