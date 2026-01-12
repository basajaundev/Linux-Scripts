#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GITHUB_API_BASE="https://api.github.com"
CONFIG_DIR="$HOME/.config/git-helper"
CONFIG_FILE="$CONFIG_DIR/config"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

load_config() {
    mkdir -p "$CONFIG_DIR"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
GITHUB_TOKEN="$GITHUB_TOKEN"
GITHUB_USER="$GITHUB_USER"
DEFAULT_REPO_OWNER="$DEFAULT_REPO_OWNER"
EOF
    chmod 600 "$CONFIG_FILE"
}

check_github_token() {
    if [ -z "$GITHUB_TOKEN" ]; then
        log_error "No GitHub token configured. Run: git-helper config"
        exit 1
    fi
}

github_api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    curl -s -X "$method" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        "${GITHUB_API_BASE}${endpoint}" \
        ${data:+-d "$data"}
}

check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository"
        exit 1
    fi
}

cmd_status() {
    check_git_repo
    echo -e "${BLUE}Git Status:${NC}"
    git status -sb
    echo ""
    echo -e "${BLUE}Unstaged changes:${NC}"
    git diff --stat
    echo ""
    echo -e "${BLUE}Staged changes:${NC}"
    git diff --cached --stat
}

cmd_commit() {
    check_git_repo
    local message="$1"
    
    if [ -z "$message" ]; then
        log_error "Commit message required. Usage: git-helper commit \"message\""
        exit 1
    fi
    
    local branch=$(git rev-parse --abbrev-ref HEAD)
    log_info "Committing to branch: $branch"
    
    git add -A
    git commit -m "$message"
    log_success "Commit created: $message"
}

cmd_push() {
    check_git_repo
    local remote="${1:-origin}"
    local branch=$(git rev-parse --abbrev-ref HEAD)
    
    log_info "Pushing to $remote/$branch"
    git push "$remote" "$branch"
    log_success "Pushed successfully"
}

cmd_pull() {
    check_git_repo
    local remote="${1:-origin}"
    local branch=$(git rev-parse --abbrev-ref HEAD)
    
    log_info "Pulling from $remote/$branch"
    git pull "$remote" "$branch"
    log_success "Pulled successfully"
}

cmd_branch() {
    check_git_repo
    echo -e "${BLUE}Local branches:${NC}"
    git for-each-ref --format='%(refname:short)' refs/heads | while read branch; do
        if [ "$branch" = "$(git rev-parse --abbrev-ref HEAD)" ]; then
            echo -e "  * ${GREEN}$branch${NC}"
        else
            echo "    $branch"
        fi
    done
    
    echo ""
    echo -e "${BLUE}Remote branches:${NC}"
    git for-each-ref --format='%(refname:short)' refs/remotes | while read branch; do
        echo "    $branch"
    done
}

cmd_checkout() {
    check_git_repo
    local branch="$1"
    
    if [ -z "$branch" ]; then
        log_error "Branch name required. Usage: git-helper checkout <branch>"
        exit 1
    fi
    
    if git show-ref --verify --quiet refs/heads/"$branch"; then
        git checkout "$branch"
        log_success "Switched to branch: $branch"
    elif git ls-remote --exit-code origin "$branch" 2>/dev/null; then
        git checkout -b "$branch" origin/"$branch"
        log_success "Checked out remote branch: $branch"
    else
        log_error "Branch '$branch' not found locally or remotely"
        exit 1
    fi
}

cmd_create_branch() {
    check_git_repo
    local branch="$1"
    local from_branch="${2:-$(git rev-parse --abbrev-ref HEAD)}"
    
    if [ -z "$branch" ]; then
        log_error "Branch name required. Usage: git-helper create-branch <name> [from-branch]"
        exit 1
    fi
    
    git checkout "$from_branch"
    git checkout -b "$branch"
    log_success "Created branch '$branch' from '$from_branch'"
}

cmd_delete_branch() {
    check_git_repo
    local branch="$1"
    local force="${2:-}"
    
    if [ -z "$branch" ]; then
        log_error "Branch name required. Usage: git-helper delete-branch <name>"
        exit 1
    fi
    
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$branch" = "$current_branch" ]; then
        log_error "Cannot delete current branch"
        exit 1
    fi
    
    if [ "$force" = "-f" ]; then
        git branch -D "$branch"
        log_success "Force deleted branch: $branch"
    else
        git branch -d "$branch"
        log_success "Deleted branch: $branch"
    fi
}

cmd_stash() {
    check_git_repo
    local message="$1"
    
    if [ -z "$message" ]; then
        message="WIP: $(git rev-parse --abbrev-ref HEAD)"
    fi
    
    git stash push -m "$message"
    log_success "Stashed changes with message: $message"
}

cmd_stash_pop() {
    check_git_repo
    local index="${1:-0}"
    
    git stash list | head -n $((index + 1))
    git stash pop stash@{${index}} 2>/dev/null || {
        log_error "Invalid stash index"
        exit 1
    }
    log_success "Popped stash#$index"
}

cmd_log() {
    check_git_repo
    local limit="${1:-10}"
    git log --oneline -n "$limit"
}

cmd_diff() {
    check_git_repo
    local commit="${1:-HEAD}"
    git diff "$commit"~1 "$commit" --stat
    echo ""
    git diff "$commit"~1 "$commit"
}

cmd_github_repo_create() {
    check_github_token
    
    local name="$1"
    local description="$2"
    local private="${3:-false}"
    local auto_init="${4:-true}"
    
    if [ -z "$name" ]; then
        log_error "Repository name required. Usage: git-helper github repo-create <name> [description] [--private]"
        exit 1
    fi
    
    local data=$(cat << EOF
{
    "name": "$name",
    "description": "$description",
    "private": $private,
    "auto_init": $auto_init
}
EOF
)
    
    local response=$(github_api_request "POST" "/user/repos" "$data")
    local repo_url=$(echo "$response" | grep -o '"clone_url": "[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$repo_url" ]; then
        log_success "Repository created: $repo_url"
        echo "$repo_url"
    else
        log_error "Failed to create repository"
        echo "$response"
        exit 1
    fi
}

cmd_github_repo_list() {
    check_github_token
    local user="${1:-$GITHUB_USER}"
    local page="${2:-1}"
    local per_page="${3:-30}"
    
    if [ -z "$user" ]; then
        log_error "Username required. Usage: git-helper github repo-list [username]"
        exit 1
    fi
    
    local response=$(github_api_request "GET" "/users/$user/repos?page=$page&per_page=$per_page&sort=updated")
    echo "$response" | grep -o '"full_name": "[^"]*"' | cut -d'"' -f4 | head -20
}

cmd_github_issue_list() {
    check_github_token
    local repo="$1"
    local state="${2:-open}"
    
    if [ -z "$repo" ]; then
        log_error "Repository required (owner/repo). Usage: git-helper github issue-list <owner/repo> [state]"
        exit 1
    fi
    
    local response=$(github_api_request "GET" "/repos/$repo/issues?state=$state")
    echo "$response" | grep -E '"number"|"title"|"state"' | paste - - - | head -20 | while read line; do
        echo "$line" | sed 's/"//g' | sed 's/,//g' | awk '{print "Issue " $1 ": " $3}'
    done
}

cmd_github_issue_create() {
    check_github_token
    local repo="$1"
    local title="$2"
    local body="$3"
    
    if [ -z "$repo" ] || [ -z "$title" ]; then
        log_error "Usage: git-helper github issue-create <owner/repo> \"title\" [body]"
        exit 1
    fi
    
    local data=$(cat << EOF
{
    "title": "$title",
    "body": "$body"
}
EOF
)
    
    local response=$(github_api_request "POST" "/repos/$repo/issues" "$data")
    local issue_url=$(echo "$response" | grep -o '"html_url": "[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$issue_url" ]; then
        log_success "Issue created: $issue_url"
    else
        log_error "Failed to create issue"
        echo "$response"
        exit 1
    fi
}

cmd_github_pr_list() {
    check_github_token
    local repo="$1"
    local state="${2:-open}"
    
    if [ -z "$repo" ]; then
        log_error "Repository required (owner/repo). Usage: git-helper github pr-list <owner/repo> [state]"
        exit 1
    fi
    
    local response=$(github_api_request "GET" "/repos/$repo/pulls?state=$state")
    echo "$response" | grep -E '"number"|"title"|"state"|"head"."ref"' | paste - - - - | head -20 | while read line; do
        echo "$line" | sed 's/"//g' | sed 's/,//g' | awk '{print "PR#" $1 ": " $3 " (" $7 ")"}'
    done
}

cmd_github_pr_create() {
    check_github_token
    local repo="$1"
    local title="$2"
    local body="$3"
    local head="$4"
    local base="${5:-main}"
    
    if [ -z "$repo" ] || [ -z "$title" ] || [ -z "$head" ]; then
        log_error "Usage: git-helper github pr-create <owner/repo> \"title\" \"body\" <head-branch> [base-branch]"
        exit 1
    fi
    
    local data=$(cat << EOF
{
    "title": "$title",
    "body": "$body",
    "head": "$head",
    "base": "$base"
}
EOF
)
    
    local response=$(github_api_request "POST" "/repos/$repo/pulls" "$data")
    local pr_url=$(echo "$response" | grep -o '"html_url": "[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$pr_url" ]; then
        log_success "Pull Request created: $pr_url"
    else
        log_error "Failed to create pull request"
        echo "$response"
        exit 1
    fi
}

cmd_github_clone() {
    local repo="$1"
    local dir="$2"
    
    if [ -z "$repo" ]; then
        log_error "Repository required (owner/repo). Usage: git-helper github clone <owner/repo> [directory]"
        exit 1
    fi
    
    if [ -z "$dir" ]; then
        dir=$(echo "$repo" | cut -d'/' -f2)
    fi
    
    if [ -n "$GITHUB_TOKEN" ]; then
        git clone "https://$GITHUB_TOKEN@github.com/$repo.git" "$dir"
    else
        git clone "https://github.com/$repo.git" "$dir"
    fi
    
    log_success "Cloned $repo to $dir"
}

cmd_changelog() {
    check_git_repo
    local from_tag="${1:-}"
    local to_tag="${2:-HEAD}"
    local format="${3:-markdown}"
    
    if [ -z "$from_tag" ]; then
        local tags=$(git tag --sort=-creatordate | head -5)
        if [ -n "$tags" ]; then
            from_tag=$(echo "$tags" | tail -1)
            log_info "Using tag: $from_tag"
        fi
    fi
    
    local commits
    if [ -n "$from_tag" ]; then
        commits=$(git log "$from_tag".."$to_tag" --oneline --pretty=format:"%h|%s|%an" 2>/dev/null)
    else
        commits=$(git log --oneline --pretty=format:"%h|%s|%an" -n 50)
    fi
    
    if [ "$format" = "markdown" ]; then
        echo "# Changelog"
        echo ""
        echo "From: $from_tag -> To: $to_tag"
        echo ""
        echo "## Commits"
        echo ""
        echo "$commits" | while read line; do
            local hash=$(echo "$line" | cut -d'|' -f1)
            local msg=$(echo "$line" | cut -d'|' -f2)
            local author=$(echo "$line" | cut -d'|' -f3)
            echo "- \`$hash\` $msg (by $author)"
        done
    else
        echo "$commits"
    fi
}

cmd_config() {
    local token="$1"
    local user="$2"
    
    if [ -n "$token" ]; then
        GITHUB_TOKEN="$token"
        log_info "GitHub token configured"
    fi
    
    if [ -n "$user" ]; then
        GITHUB_USER="$user"
        log_info "GitHub username configured: $user"
    fi
    
    if [ -z "$token" ] && [ -z "$user" ]; then
        echo "Current configuration:"
        echo "  GitHub Token: ${GITHUB_TOKEN:0:10}..."
        echo "  GitHub User: $GITHUB_USER"
    fi
    
    save_config
    log_success "Configuration saved"
}

cmd_sync() {
    check_git_repo
    log_info "Syncing with remote..."
    git fetch origin
    
    local branch=$(git rev-parse --abbrev-ref HEAD)
    local remote_branch="origin/$branch"
    
    if git rev-parse --verify "$remote_branch" > /dev/null 2>&1; then
        local local_commit=$(git rev-parse "$branch")
        local remote_commit=$(git rev-parse "$remote_branch")
        
        if [ "$local_commit" = "$remote_commit" ]; then
            log_success "Already up to date"
        else
            log_info "Local is ahead/behind remote. Pulling changes..."
            git pull origin "$branch"
            log_success "Synced successfully"
        fi
    else
        log_warn "Remote branch not found. Push to create it."
    fi
}

cmd_undo() {
    check_git_repo
    local type="$1"
    
    case "$type" in
        commit)
            git reset --soft HEAD~1
            log_success "Undid last commit (changes staged)"
            ;;
        last)
            git reset --mixed HEAD~1
            log_success "Undid last commit (changes unstaged)"
            ;;
        file)
            local file="$2"
            if [ -n "$file" ]; then
                git checkout HEAD -- "$file"
                log_success "Restored $file to last commit"
            else
                log_error "File path required"
                exit 1
            fi
            ;;
        *)
            log_error "Usage: git-helper undo <commit|last|file> [file]"
            exit 1
            ;;
    esac
}

cmd_help() {
    echo "git-helper - Git helper with GitHub integration"
    echo ""
    echo "Usage: git-helper <command> [options]"
    echo ""
    echo "Git Commands:"
    echo "  status              Show git status"
    echo "  commit <msg>        Create a commit with message"
    echo "  push [remote]       Push to remote (default: origin)"
    echo "  pull [remote]       Pull from remote (default: origin)"
    echo "  branch              List all branches"
    echo "  checkout <branch>   Switch to branch"
    echo "  create-branch <name> [from]  Create new branch"
    echo "  delete-branch <name> [-f]    Delete branch (use -f to force)"
    echo "  stash [msg]         Stash changes"
    echo "  stash-pop [index]   Pop stash by index"
    echo "  log [limit]         Show commit log"
    echo "  diff [commit]       Show diff for commit"
    echo "  sync                Sync with remote"
    echo "  undo <type>         Undo last action"
    echo ""
    echo "GitHub Commands:"
    echo "  github repo-create <name> [desc] [--private]  Create GitHub repository"
    echo "  github repo-list [user]                       List user repositories"
    echo "  github issue-list <owner/repo> [state]        List issues"
    echo "  github issue-create <owner/repo> \"title\" [body]  Create issue"
    echo "  github pr-list <owner/repo> [state]           List pull requests"
    echo "  github pr-create <owner/repo> \"title\" \"body\" <head> [base]  Create PR"
    echo "  github clone <owner/repo> [dir]               Clone repository"
    echo ""
    echo "Other Commands:"
    echo "  changelog [from-tag] [to-tag] [format]  Generate changelog"
    echo "  config [token] [user]                   Configure GitHub credentials"
    echo "  help                                     Show this help"
    echo ""
    echo "Examples:"
    echo "  git-helper commit \"Fix login bug\""
    echo "  git-helper push origin"
    echo "  git-helper github repo-create myproject \"My Project\""
    echo "  git-helper changelog v1.0.0 v1.1.0"
}

main() {
    load_config
    
    local command="${1:-}"
    shift 2>/dev/null || true
    
    case "$command" in
        status|commit|push|pull|branch|checkout|create-branch|delete-branch)
            cmd_${command} "$@"
            ;;
        stash|stash-pop)
            cmd_${command} "$@"
            ;;
        log|diff|undo)
            cmd_${command} "$@"
            ;;
        sync)
            cmd_sync
            ;;
        changelog)
            cmd_changelog "$@"
            ;;
        config)
            cmd_config "$@"
            ;;
        github)
            local subcommand="$1"
            shift
            case "$subcommand" in
                repo-create|repo-list|issue-list|issue-create|pr-list|pr-create|clone)
                    cmd_github_${subcommand} "$@"
                    ;;
                *)
                    log_error "Unknown github command: $subcommand"
                    cmd_help
                    exit 1
                    ;;
            esac
            ;;
        help|--help|-h)
            cmd_help
            ;;
        "")
            cmd_help
            ;;
        *)
            log_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
