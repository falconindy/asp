package_init() {
  local do_update=1 pkgname=$1

  if [[ $1 = -n ]]; then
    do_update=0
    shift
    pkgname=$1
  fi

  package_find_remote "$pkgname" "$2" || return 1

  (( do_update )) || return 0

  remote_is_tracking "${!2}" "$pkgname" ||
      remote_update_refs "${!2}" "packages/$pkgname"
}

package_find_remote() {
  local pkgname=$1

  # fastpath, checks local caches only
  for r in "${ARCH_GIT_REPOS[@]}"; do
    if remote_is_tracking "$r" "$pkgname"; then
      printf -v "$2" %s "$r"
      return 0
    fi
  done

  # slowpath, needs to talk to the remote
  for r in "${ARCH_GIT_REPOS[@]}"; do
    if remote_has_package "$r" "$pkgname"; then
      printf -v "$2" %s "$r"
      return 0
    fi
  done

  log_error 'unknown package: %s' "$pkgname"

  return 1
}

package_log() {
  local pkgname=$1 method=$2 logargs remote

  package_init "$pkgname" remote || return

  case $method in
    shortlog)
      logargs=(--pretty=oneline)
      ;;
    difflog)
      logargs=(-p)
      ;;
    log)
      logargs=()
      ;;
    *)
      die 'internal error: unknown log method: %s' "$method"
      ;;
  esac

  git log "${logargs[@]}" "$remote/packages/$pkgname" -- trunk/
}

package_show_file() {
  local pkgname=$1 file=${2:-PKGBUILD} remote repo subtree

  if [[ $pkgname = */* ]]; then
    IFS=/ read -r repo pkgname <<<"$pkgname"
  fi

  package_init "$pkgname" remote || return

  if [[ $file != */* ]]; then
    if [[ $repo ]]; then
      subtree=repos/$repo-$OPT_ARCH/
    else
      subtree=trunk/
    fi
  fi

  git show "remotes/$remote/packages/$pkgname:$subtree$file"
}

package_list_files() {
  local pkgname=$1 remote

  if [[ $pkgname = */* ]]; then
    IFS=/ read -r repo pkgname <<<"$pkgname"
  fi

  package_init "$pkgname" remote || return

  if [[ $repo ]]; then
    subtree=repos/$repo-$OPT_ARCH
  else
    subtree=trunk
  fi


  git ls-tree -r --name-only "remotes/$remote/packages/$pkgname" "$subtree" |
      awk -v prefix=$subtree/ 'sub(prefix, "")'
}

package_export() {
  local pkgname=$1 remote repo arch path

  if [[ $pkgname = */* ]]; then
    IFS=/ read -r repo pkgname <<<"$pkgname"
  fi

  package_init "$pkgname" remote || return 1

  if [[ $repo ]]; then
    subtree=repos/$repo-$OPT_ARCH
  else
    subtree=trunk
  fi

  if [[ -z $(git ls-tree "remotes/$remote/packages/$pkgname" "$subtree/") ]]; then
    if [[ $repo ]]; then
      log_error "package '%s' not found in repo '%s-%s'" "$pkgname" "$repo" "$OPT_ARCH"
      return 1
    else
      log_error "package '%s' has no trunk directory!" "$pkgname"
      return 1
    fi
  fi

  if (( ! OPT_FORCE )); then
    # shellcheck disable=SC2154
    mkdir "$startdir/$pkgname" || return 1
  fi

  log_info 'exporting %s:%s' "$pkgname" "$subtree"
  git archive --format=tar "remotes/$remote/packages/$pkgname" "$subtree/" |
      bsdtar -C "$startdir" -s ",^$subtree/,$pkgname/," -xf - "$subtree/"
}

package_checkout() {
  local pkgname=$1 remote

  package_init "$pkgname" remote || return 1

  git show-ref -q "refs/heads/$remote/packages/$pkgname" ||
      git branch -qf --no-track {,}"$remote/packages/$pkgname"

  git clone "$ASPROOT" --single-branch --branch "$remote/packages/$pkgname" \
    "$startdir/$pkgname" || return 1

  git --git-dir="$startdir/$pkgname/.git" config pull.rebase true
}

package_get_repos_with_arch() {
  local pkgname=$1 remote=$2
  local path arch repo

  while read -r path; do
    IFS=/- read -r _ repo arch <<<"$path"
    printf '%s %s\n' "$repo" "$arch"
  done < <(git ls-tree --name-only "$remote/packages/$pkgname" repos/)
}

package_get_arches() {
  local pkgname=$1 remote arch
  declare -A arches

  package_init "$pkgname" remote || return 1

  while read -r _ arch; do
    arches["$arch"]=1
  done < <(package_get_repos_with_arch "$pkgname" "$remote")

  printf '%s\n' "${!arches[@]}"
}

package_get_repos() {
  local pkgname=$1 remote repo
  declare -A repos

  package_init "$pkgname" remote || return 1

  while read -r repo _; do
    repos["$repo"]=1
  done < <(package_get_repos_with_arch "$pkgname" "$remote")

  printf '%s\n' "${!repos[@]}"
}

package_untrack() {
  local pkgname=$1 remote=$2

  if git show-ref -q "refs/heads/$remote/packages/$pkgname"; then
    git branch -D "$remote/packages/$pkgname"
  fi
}
