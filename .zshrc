


# ======================================
# PATHS
# ======================================

#export JAVA_HOME=/usr/bin/java (original) 
export JAVA_HOME=/Library/Java/JavaVirtualMachines/adoptopenjdk-8.jdk/Contents/Home

# ======================================
# ZSH settings 
# ======================================

# Path to your oh-my-zsh installation.
export ZSH="/Users/bladzicha/.oh-my-zsh"
ZSH_THEME="muse"

# Uncomment the following line to automatically update without prompting.
DISABLE_UPDATE_PROMPT="true"

# Uncomment the following line to change how often to auto-update (in days).
export UPDATE_ZSH_DAYS=13

# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
plugins=(git)

source $ZSH/oh-my-zsh.sh

# ======================================
# ALIASES
# ======================================

# Better command defaults
alias ...='cd ../..'
alias ....='cd ../../..'
alias ls='ls -lah'
alias env='env | sort'
alias ssh-add-keys=ssh-add ~/.ssh/id_elsevier
alias list-ports='netstat -anv'

# ======================================
# SSH (not sure this works as expected with ssh key needing a passphrase, run `ssh-add <individual identity>` instead)
# ======================================

export SSH_AUTH_SOCK="$HOME/.ssh/agent-socket"
ssh-add -l >& /dev/null
if [[ $? -eq 2 ]]
then
  rm -f "$SSH_AUTH_SOCK"
  eval $(ssh-agent -a "$SSH_AUTH_SOCK")
  ssh-add -k $HOME/.ssh/recs-*.id_rsa
fi

# ======================================
# File helpers                      
# ======================================

# Display the full path of a file
# full-path ./foo.txt
function full-path() {
    declare fnam=$1

    if [ -d "$fnam" ]; then
        (cd "$fnam"; pwd)
    elif [ -f "$fnam" ]; then
        if [[ $fnam == */* ]]; then
            echo "$(cd "${1%/*}"; pwd)/${1##*/}"
        else
            echo "$(pwd)/$fnam"
        fi
    fi
}

# Tar a file
# tarf my-dir
function tarf() {
    declare fnam=$1
    tar -zcvf "${fnam%/}".tar.gz "$1"
}

# Untar a file
# untarf my-dir.tar.gz
function untarf() {
    declare fnam=$1
    tar -zxvf "$1"
}

# ======================================
# Long running jobs
# ======================================

# Notify me when something completes
# Usage: do-something-long-running ; tell-me "optional message"
function tell-me() {
    exitCode="$?"

    if [[ $exitCode -eq 0 ]]; then
        exitStatus="SUCCEEDED"
    else
        exitStatus="FAILED"
    fi

    if [[ $# -lt 1 ]] ; then
        msg="${exitStatus}"
    else
        msg="${exitStatus} : $1"
    fi

    if-darwin && {
        osascript -e "display notification \"$msg\" with title \"tell-me\""
    }

    if-linux && {
        notify-send -t 2000 "tell-me" "$msg"
    }
}

# Helper function to notify when the output of a command changes
# Usage:
#   function watch-directory() {
#       f() {
#           ls
#       }
#
#       notify-on-change f 1 "Directory contents changed"
#   }
function notify-on-change() {
    local f=$1
    local period=$2
    local message=$3
    local tmpfile=$(mktemp)

    $f > "${tmpfile}"

    {
        while true
        do
            sleep ${period}
            (diff "${tmpfile}" <($f)) || break
        done

        tell-me "${message}"
    } > /dev/null 2>&1 & disown
}

# ======================================
# AWS authentication               
# ======================================

alias aws-which="env | grep AWS | sort"
alias aws-clear-variables="for i in \$(aws-which | cut -d= -f1,1 | paste -); do unset \$i; done"

function aws-switch-role() {
    declare roleARN=$1 profile=$2

    LOGIN_OUTPUT="$(aws-adfs login --adfs-host federation.reedelsevier.com --region us-east-1 --session-duration 14400 --role-arn $roleARN --env --profile $profile --printenv | grep export)"
    AWS_ENV="$(echo $LOGIN_OUTPUT | grep export)"
    eval $AWS_ENV
    export AWS_REGION=us-east-1
    aws-which
}

function aws-developer-role() {
    declare accountId=$1 role=$2 profile=$3
    aws-switch-role "arn:aws:iam::${accountId}:role/${role}" "${profile}"
}

alias aws-recs-dev="aws-developer-role $SECRET_ACC_RECS_DEV ADFS-EnterpriseAdmin aws-rap-recommendersdev"
alias aws-recs-prod="aws-developer-role $SECRET_ACC_RECS_PROD ADFS-EnterpriseAdmin aws-rap-recommendersprod"

function aws-recs-login() {
    if [[ $# -ne 1 ]]; then
        echo "Usage: aws-recs-login (dev|staging|live)"
    else
        local recsEnv=$1

        case "${recsEnv}" in
            dev*)
                aws-recs-dev
            ;;

            staging*)
                aws-recs-dev
            ;;

            live*)
                aws-recs-prod
            ;;

            *)
                echo "ERROR: Unrecognised environment ${recsEnv}"
                return -1
            ;;
        esac
    fi
}
compdef "_arguments \
    '1:environment arg:(dev staging live)'" \
    aws-recs-login


# ======================================
# AWS helper functions
# ======================================

# AWS CLI commands pointing at localstack
alias aws-localstack='AWS_DEFAULT_REGION=us-east-1 aws --endpoint-url=http://localhost:4566'

# List ECR images
function aws-ecr-images() {
    local repos=$(aws ecr describe-repositories \
        | jq -r ".repositories[].repositoryName" \
        | sort)

    while IFS= read -r repo; do
        echo $repo
        AWS_PAGER="" aws ecr describe-images --repository-name "${repo}" \
            | jq -r '.imageDetails[] | select(has("imageTags")) | .imageTags[] | select(test( "^\\d+\\.\\d+\\.\\d+$" ))' \
            | sort
        echo
    done <<< "$repos"
}

# Describe OpenSearch clusters
function aws-opensearch-describe-clusters() {
    while IFS=, read -rA domainName
    do
        aws opensearch describe-domain --domain-name "${domainName}"
    done < <(aws opensearch list-domain-names | jq -r -c '.DomainNames[].DomainName') \
        | jq -s \
        | jq -r '["DomainName", "InstanceType", "InstanceCount", "MasterType", "MasterCount"],(.[].DomainStatus | [.DomainName, (.ClusterConfig | .InstanceType, .InstanceCount, .DedicatedMasterType, .DedicatedMasterCount)]) | @tsv' \
        | tabulate-by-tab
}

# List lambda statuses
function aws-lambda-statuses() {
    aws lambda list-event-source-mappings \
        | jq -r ".EventSourceMappings[] | [.FunctionArn, .EventSourceArn, .State, .UUID] | @tsv" \
        | tabulate-by-tab \
        | sort \
        | highlight red '.*Disabled.*' \
        | highlight yellow '.*\(Enabling\|Disabling\|Updating\).*'
}

# List EMR statuses
function aws-emr-status() {
    if [[ $# -ne 1 ]]; then
        echo "Usage: aws-recs-login (dev|staging|live)"
    else
        local clusterId=$1
        aws emr list-steps \
            --cluster-id "${clusterId}" \
            | jq -r '.Steps[] | [.Name, .Status.State, .Status.Timeline.StartDateTime, .Status.Timeline.EndDateTime] | @csv' \
            | column -t -s ',' \
            | sed 's/"//g'

        aws emr describe-cluster \
            --cluster-id "${clusterId}" \
            | jq -r ".Cluster | (.LogUri + .Id)" \
            | sed 's/s3n:/s3:/'
    fi
}

# Open the specified S3 bucket in the web browser
function aws-s3-open() {
    local s3Path=$1
    echo "Opening '$s3Path'"
    echo "$s3Path" \
        | gsed -e 's/^.*s3:\/\/\(.*\)/\1/' \
        | gsed -e 's/^/https:\/\/s3.console.aws.amazon.com\/s3\/buckets\//' \
        | gsed -e 's/$/?region=us-east-1/' \
        | xargs open
}

# Display available IPs in each subnet
function aws-subnet-available-ips() {
    aws ec2 describe-subnets \
        | jq -r ".Subnets[] | [ .SubnetId, .AvailableIpAddressCount ] | @tsv" \
        | strip-quotes \
        | tabulate-by-tab
}

# Display service quotas for EC2
function aws-ec2-service-quotas() {
    aws service-quotas list-service-quotas --service-code ec2 \
        | jq -r '(.Quotas[] | ([.QuotaName, .Value])) | @tsv' \
        | strip-quotes \
        | tabulate-by-tab
}

# Download data pipeline definitions to local files
function aws-datapipeline-download-definitions() {
    while IFS=, read -rA x
    do
        pipelineId=${x[@]:0:1}
        pipelineName=$(echo "${x[@]:1:1}" | tr '[A-Z]' '[a-z]' | tr ' ' '-')
        echo $pipelineName
        aws datapipeline get-pipeline-definition --pipeline-id $pipelineId \
            | jq '.' \
            > "pipeline-definition-${pipelineName}"
    done < <(aws datapipeline list-pipelines | jq --raw-output '.pipelineIdList[] | [.id, .name] | @csv' | strip-quotes) \
}

# Display data pipeline instance requirements
function aws-datapipeline-instance-requirements() {
    while IFS=, read -rA x
    do
        pipelineId=${x[@]:0:1}
        pipelineName=${x[@]:1:1}
        aws datapipeline get-pipeline-definition --pipeline-id $pipelineId \
            | jq --raw-output ".values | [\"$pipelineName\", .my_master_instance_type, \"1\", .my_core_instance_type, .my_core_instance_count, .my_env_subnet_private]| @csv"
    done < <(aws datapipeline list-pipelines | jq --raw-output '.pipelineIdList[] | [.id, .name] | @csv' | strip-quotes) \
        | strip-quotes \
        | tabulate-by-comma
}

# Display AWS secrets
function aws-secrets() {
    local secretsNames=$(aws secretsmanager list-secrets | jq -r '.SecretList[].Name')

    while IFS= read -r secret ; do
        echo ${secret}
        aws secretsmanager list-secrets \
            | jq -r ".SecretList[] | select(.Name == \"$secret\") | .Tags[] // [] | select(.Key == \"Description\") | .Value"
        aws secretsmanager get-secret-value --secret-id "$secret"\
            | jq '.SecretString | fromjson'
        echo
    done <<< "${secretsNames}"
}

function aws-ip() {
    local hostname=$1
    echo "${hostname}" | sed -r 's/ip-(.+)\.ec2\.internal/\1/g' | sed -r 's/-/./g'
}

# ======================================
# GIT
# ======================================

# Git Aliases
alias git-clean='git clean -X -f -d'
alias gst='git status'
alias glp='git log --graph --pretty='\''%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'

# For each directory within the current directory, if the directory is a Git
# repository then execute the supplied function 
function git-for-each-repo() {
    setopt local_options glob_dots
    for fnam in *; do
        if [[ -d $fnam ]]; then
            pushd "$fnam" > /dev/null || return 1
            if git rev-parse --git-dir > /dev/null 2>&1; then
                "$@"
            fi
            popd > /dev/null || return 1
        fi
    done
}

# For each directory within the current directory, if the directory is a Git
# repository then execute the supplied function in parallel
function git-for-each-repo-parallel() {
    local dirs=$(find . -type d -depth 1)

    echo "$dirs" \
        | env_parallel --env "$1" -j20 \
            "
            pushd {} > /dev/null;                               \
            if git rev-parse --git-dir > /dev/null 2>&1; then   \
                $@;                                             \
            fi;                                                 \
            popd > /dev/null;                                   \
            "
}

# For each repo within the current directory, pull the repo
function git-repos-pull() {
    pull-repo() {
        echo "Pulling $(basename $PWD)"
        git pull -r --autostash
        echo
    }

    git-for-each-repo-parallel pull-repo 
    git-repos-status
}

# For each repo within the current directory, fetch the repo
function git-repos-fetch() {
    local args=$*

    fetch-repo() {
        echo "Fetching $(basename $PWD)"
        git fetch ${args}
        echo
    }

    git-for-each-repo-parallel fetch-repo 
    git-repos-status
}

# Parse Git status into a Zsh associative array
function git-parse-repo-status() {
    local aheadAndBehind
    local ahead=0
    local behind=0
    local added=0
    local modified=0
    local deleted=0
    local renamed=0
    local untracked=0
    local stashed=0

    branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null)
    ([[ $? -ne 0 ]] || [[ -z "$branch" ]]) && branch="unknown"

    aheadAndBehind=$(git status --porcelain=v1 --branch | perl -ne '/\[(.+)\]/ && print $1' )
    ahead=$(echo $aheadAndBehind | perl -ne '/ahead (\d+)/ && print $1' )
    [[ -z "$ahead" ]] && ahead=0
    behind=$(echo $aheadAndBehind | perl -ne '/behind (\d+)/ && print $1' )
    [[ -z "$behind" ]] && behind=0

    # See https://git-scm.com/docs/git-status for output format
    while read -r line; do
      # echo "$line"
      echo "$line" | gsed -r '/^[A][MD]? .*/!{q1}'   > /dev/null && (( added++ ))
      echo "$line" | gsed -r '/^[M][MD]? .*/!{q1}'   > /dev/null && (( modified++ ))
      echo "$line" | gsed -r '/^[D][RCDU]? .*/!{q1}' > /dev/null && (( deleted++ ))
      echo "$line" | gsed -r '/^[R][MD]? .*/!{q1}'   > /dev/null && (( renamed++ ))
      echo "$line" | gsed -r '/^[\?][\?] .*/!{q1}'   > /dev/null && (( untracked++ ))
    done < <(git status --porcelain)

    stashed=$(git stash list | wc -l)

    unset gitRepoStatus
    typeset -gA gitRepoStatus
    gitRepoStatus[branch]=$branch
    gitRepoStatus[ahead]=$ahead
    gitRepoStatus[behind]=$behind
    gitRepoStatus[added]=$added
    gitRepoStatus[modified]=$modified
    gitRepoStatus[deleted]=$deleted
    gitRepoStatus[renamed]=$renamed
    gitRepoStatus[untracked]=$untracked
    gitRepoStatus[stashed]=$stashed
}

# For each repo within the current directory, display the repository status
function git-repos-status() {
    display-status() {
        git-parse-repo-status
        repo=$(basename $PWD) 

        local branchColor="${COLOR_RED}"
        if [[ "$gitRepoStatus[branch]" =~ (main) ]]; then
            branchColor="${COLOR_GREEN}"
        fi
        local branch="${branchColor}$gitRepoStatus[branch]${COLOR_NONE}"

        local sync="${COLOR_GREEN}in-sync${COLOR_NONE}"
        if (( $gitRepoStatus[ahead] > 0 )) && (( $gitRepoStatus[behind] > 0 )); then
            sync="${COLOR_RED}ahead/behind${COLOR_NONE}"
        elif (( $gitRepoStatus[ahead] > 0 )); then
            sync="${COLOR_RED}ahead${COLOR_NONE}"
        elif (( $gitRepoStatus[behind] > 0 )); then
            sync="${COLOR_RED}behind${COLOR_NONE}"
        fi

        local dirty="${COLOR_GREEN}clean${COLOR_NONE}"
        (($gitRepoStatus[added] + $gitRepoStatus[modified] + $gitRepoStatus[deleted] + $gitRepoStatus[renamed] > 0)) && dirty="${COLOR_RED}dirty${COLOR_NONE}"

        echo "${branch},${sync},${dirty},${repo}"
    }

    git-for-each-repo display-status | column -t -s ','
}

# For each repo within the current directory, display whether the repo contains
# unmerged branches locally
function git-repos-unmerged-branches() {
    display-unmerged-branches() {
        local cmd="git branch --no-merged main"
        unmergedBranches=$(eval "$cmd") 
        if [[ $unmergedBranches = *[![:space:]]* ]]; then
            echo "$fnam"
            eval "$cmd"
            echo
        fi
    }

    git-for-each-repo display-unmerged-branches
}

# For each repo within the current directory, display whether the repo contains
# unmerged branches locally and remote
function git-repos-unmerged-branches-all() {
    display-unmerged-branches-all() {
        local cmd="git branch --all --no-merged main"
        unmergedBranches=$(eval "$cmd") 
        if [[ $unmergedBranches = *[![:space:]]* ]]; then
            echo "$fnam"
            eval "$cmd"
            echo
        fi
    }

    git-for-each-repo display-unmerged-branches-all
}

# For each repo within the current directory, display stashes
function git-repos-code-stashes() {
    stashes() {
        local cmd="git stash list"
        local output=$(eval "$cmd") 
        if [[ $output = *[![:space:]]* ]]; then
            pwd
            eval "$cmd"
            echo
        fi
    }

    git-for-each-repo stashes 
}

# For each repo within the current directory, display recent changes in the repo
function git-repos-recent() {
    recent() {
        local cmd="git --no-pager log-recent --author='Jenkins' --invert-grep"
        local output=$(eval "$cmd") 
        if [[ $output = *[![:space:]]* ]]; then
            pwd
            eval "$cmd"
            echo
            echo
        fi
    }

    git-for-each-repo recent 
}

# For each repo within the current directory, grep for the argument in the history
function git-repos-grep-history() {
    local str=$1

    check-history() {
        local str="$1"
        pwd
        git grep "${str}" $(git rev-list --all | tac)
        echo
    }

    git-for-each-repo-parallel check-history '"'"${str}"'"'
}

function git-repos-contributor-stats() {
    contributor-stats() {
        git --no-pager log --format="%aN" --no-merges
    }

    git-for-each-repo contributor-stats | sort | uniq -c | sort -r
}

function git-repos-authors() {
    authors() {
        git --no-pager log | grep "Author:" | sort | uniq
    }

    git-for-each-repo authors \
        | gsed 's/Author: //' \
        | gsed -r 's/|(\S+), (.+)\([^<]+\)/\2\1/' \
        | sort \
        | uniq
}


# For each directory within the current directory, generate a hacky lines of code count
function git-repos-hacky-line-count() {
    display-hacky-line-count() {
        git ls-files > ../file-list.txt
        lineCount=$(cat < ../file-list.txt | grep -e "\(scala\|py\|java\|sql\|elm\|tf\|yaml\|pp\|yml\)" | xargs cat | wc -l)
        echo "$fnam $lineCount"
        totalCount=$((totalCount + lineCount))
    }

    git-for-each-repo display-hacky-line-count | column -t -s ' ' | sort -b -k 2.1 -n --reverse
}

# Display remote branches which have been merged
function git-merged-branches() {
    git branch -r | xargs -t -n 1 git branch -r --contains
}

# Open the Git repo in the browser
#   Open repo: git-open 
#   Open file: git-open foo/bar/baz.txt
function git-open() {
    local filename=$1

    local pathInRepo
    if [[ -n "${filename}" ]]; then
        pushd $(dirname "${filename}")
        pathInRepo=$(git ls-tree --full-name --name-only HEAD $(basename "${filename}"))
    fi

    local branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null)
    ([[ $? -ne 0 ]] || [[ -z "$branch" ]]) && branch="main"

    URL=$(git config --get remote.origin.url)
    echo "Opening '$URL'"

    if [[ $URL =~ ^git@ ]]; then
        [[ -n "${pathInRepo}" ]] && pathInRepo="tree/${branch}/${pathInRepo}"

        local hostAlias=$(echo "$URL" | sed -E "s|git@(.*):(.*).git|\1|")
        local hostname=$(ssh -G "${hostAlias}" | awk '$1 == "hostname" { print $2 }')

        echo "$URL" \
            | sed -E "s|git@(.*):(.*).git|https://${hostname}/\2/${pathInRepo}|" \
            | xargs "${OPEN_CMD}"

    elif [[ $URL =~ ^https://bitbucket.org ]]; then
        echo "$URL" \
            | sed -E "s|(.*).git|\1/src/${branch}/${pathInRepo}|" \
            | xargs "${OPEN_CMD}"

    elif [[ $URL =~ ^https://github.com ]]; then
        [[ -n "${pathInRepo}" ]] && pathInRepo="tree/${branch}/${pathInRepo}"
        echo "$URL" \
            | sed -E "s|(.*).git|\1/${pathInRepo}|" \
            | xargs "${OPEN_CMD}"

    else
        echo "Failed to open due to unrecognised URL '$URL'"
    fi

    [[ -n "${filename}" ]] && popd > /dev/null 2>&1
}

function git-repos-generate-stats() {
    stats() {
        echo "Getting stats for $(basename $PWD)"
        git-generate-stats

        local fnam="git-stats.csv"

        if [[ -f "../${fnam}" ]]; then
            cat "${fnam}" | tail -n +2 >> "../${fnam}"
        else
            cat "${fnam}" > "../${fnam}"
        fi

        rm "${fnam}"
    }

    rm -f "git-stats.csv"

    git-for-each-repo stats
}

function _git_stats_authors() {
    q 'select distinct author from git-stats.csv limit 100' \
        | tail -n +2 \
        | sed -r 's/^(.*)$/"\1"/g' \
        | tr '\n' ' '
}

function whitetest() {
    if [[ $# -ne 1 ]] ; then
        echo 'Usage: git-stats-recent-commits-by-author AUTHOR'
        return 1
    fi

    local authorName="$1"
    local cutoff=$(gdate --iso-8601=seconds -u -d "70 days ago")

    q "select * from git-stats.csv where commit_date > '"${cutoff}"'" \
        | q "select * from - where author in ('"${authorName}"')" \
        | q "select repo_name, file, commit_date from - order by commit_date desc" \
        | q -D "$(printf '\t')" 'select * from -' \
        | tabulate-by-tab
}

function git-stats-top-team-committers-by-repo() {
    if [[ $# -ne 1 ]] ; then
        echo 'Usage: git-stats-top-team-committers-by-repo TEAM'
        return 1
    fi

    local team=$1
    [ "${team}" = 'recs' ]           && teamMembers="'Anna Bladzich', 'Rich Lyne', 'Reinder Verlinde', 'Stu White', 'Tess Hoad', 'Manisha Sistum'"

    q 'select repo_name, author, count(*) as total from git-stats.csv group by repo_name, author' \
        | q "select * from - where author in (${teamMembers})" \
        | q 'select *, row_number() over (partition by repo_name order by total desc) as idx from -' \
        | q 'select repo_name, author, total from - where idx <= 5' \
        | q -D "$(printf '\t')" 'select * from -' \
        | tabulate-by-tab
}
compdef "_arguments \
    '1:team arg:(recs butter-chicken spirograph)'" \
    git-stats-top-team-committers-by-repo

function git-stats-authors() {
    q 'select distinct author from git-stats.csv order by author asc' \
        | tail -n +2
}

function git-stats-total-commits-by-author() {
    if [[ $# -ne 1 ]] ; then
        echo 'Usage: git-stats-total-commits-by-author AUTHOR'
        return 1
    fi

    local authorName=$1

    q 'select repo_name, author, count(*) as total from git-stats.csv group by repo_name, author' \
        | q "select repo_name, total from - where author in ('"${authorName}"')" \
        | q -D "$(printf '\t')" 'select * from -' \
        | tabulate-by-tab
}

function git-stats-list-commits-by-author() {
    if [[ $# -ne 1 ]] ; then
        echo 'Usage: git-stats-list-commits-by-author AUTHOR'
        return 1
    fi

    local authorName=$1

    q "select * from git-stats.csv where author in ('"${authorName}"')" \
        | q "select distinct repo_name, commit_date, comment from - order by commit_date desc" \
        | q -D "$(printf '\t')" 'select * from -' \
        | tabulate-by-tab
}

function git-stats-total-commits-by-author-per-month() {
    if [[ $# -ne 1 ]] ; then
        echo 'Usage: git-stats-total-commits-by-author-per-month AUTHOR'
        return 1
    fi

    local authorName=$1

    q "select * from git-stats.csv where author in ('"${authorName}"')" \
        | q "select distinct repo_name, commit_date from -" \
        | q "select strftime('%Y-%m', commit_date) as 'year_month', count(*) as total from - group by year_month order by year_month desc" \
        | q -D "$(printf '\t')" 'select * from -' \
        | tabulate-by-tab
}

function git-stats-last-commits-by-repo() {
    q -O "select repo_name, max(commit_date) as last_commit from git-stats.csv where file not in ('version.sbt') group by repo_name order by last_commit desc" \
        | q -D "$(printf '\t')" 'select * from -' \
        | tabulate-by-tab
}

# ======================================
# Docker
# ======================================

alias dk='docker kill (docker ps -q); docker rm (docker ps -a -q)'

function docker-rm-instances() {
    docker ps -a -q | xargs docker stop
    docker ps -a -q | xargs docker rm
}

function docker-rm-images() {
    if confirm; then
        docker-rm-instances
        docker images -q | xargs docker rmi
        docker images | grep "<none>" | awk '{print $3}' | xargs docker rmi
    fi
}

# ======================================
# KUBE
# ======================================

alias kc=kubectl

k8() {
	if [ $1 = "dev" ]
 	then
	    aws-dev
	    aws s3 cp s3://com-elsevier-recs-dev-certs/eks/recs-eks-main-dev.conf ~/.kube/
            export KUBECONFIG=~/.kube/recs-eks-main-dev.conf
 	elif [ $1 = "prod" ]
	then
	    aws-prod
            aws s3 cp s3://com-elsevier-recs-live-certs/eks/recs-eks-main-live.conf ~/.kube/
            export KUBECONFIG=~/.kube/recs-eks-main-live.conf
	else
	    echo "Only "dev" and "prod" are valid inputs"
	    return 0
 	fi
}

# ======================================
# SBT
# ======================================

export SBT_OPTS='-Xmx2G'

alias sbt-no-ass-tests='sbt "set test in assembly := {}"'
alias sbt-test='sbt test it:test'
alias sbt-profile='sbt -Dsbt.task.timings=true'

# ======================================
# PYENV
# ======================================

eval "$(pyenv init -)"
