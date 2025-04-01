#!/bin/bash
set -e

COMMIT_EMAIL=$(git log -1 --pretty=format:'%ae')
COMMIT_NAME=$(git log -1 --pretty=format:'%an')

echo "//registry.npmjs.org/:_authToken=${NPM_TOKEN}" > ~/.npmrc

git fetch --tags
git fetch origin main:refs/remotes/origin/main

IS_PR=false
[[ "$GITHUB_EVENT_NAME" == "issue_comment" ]] && IS_PR=true

# Determine bump type
if [[ $1 == "beta" ]]; then
  VERSION_BUMP="prerelease"
else
  LAST_COMMIT_MSG=$(git log -1 --pretty=%B)
  case "$LAST_COMMIT_MSG" in
    patch:*|chore:*) VERSION_BUMP="patch" ;;
    fix:*)           VERSION_BUMP="minor" ;;
    feat:*)          VERSION_BUMP="major" ;;
    *) echo "No version bump required."; exit 0 ;;
  esac
fi

echo "Version bump type: $VERSION_BUMP"

# Detect changed packages
CHANGED=""
if [[ "$IS_PR" == "true" && -n "$PR_BRANCH" ]]; then
  git fetch origin "$PR_BRANCH:$PR_BRANCH"
  RAW_CHANGED=$(git diff --name-only origin/main..."$PR_BRANCH" | grep '^packages/' | awk -F/ '{print $2}' | sort -u)
else
  LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  RAW_CHANGED=$(git diff --name-only ${LATEST_TAG:-HEAD~1}...HEAD | grep '^packages/' | awk -F/ '{print $2}' | sort -u)
fi

for DIR in $RAW_CHANGED; do
  PKG_JSON="packages/$DIR/package.json"
  [[ -f "$PKG_JSON" ]] && PKG_NAME=$(jq -r .name "$PKG_JSON")
  [[ "$PKG_NAME" != "null" && -n "$PKG_NAME" ]] && CHANGED+="$PKG_NAME"$'\n'
done

CHANGED=$(echo "$CHANGED" | sort -u)
[[ -z "$CHANGED" ]] && echo "No changed packages. Skipping." && exit 0

echo "Changed packages:"
echo "$CHANGED"

# Determine topological publish order
TOPO_ORDER=$(yarn workspaces foreach --all --topological --no-private exec node -p "require('./package.json').name" 2>/dev/null | grep '^@' | sed 's/\[//;s/\]://')

declare -A PKG_NAME_TO_DIR
for DIR in packages/*; do
  [[ -f "$DIR/package.json" ]] && NAME=$(jq -r .name "$DIR/package.json")
  [[ "$NAME" != "null" ]] && PKG_NAME_TO_DIR[$NAME]=$(basename "$DIR")
done

# Build reverse dependency map
declare -A REVERSE_DEP_MAP
for PKG in $TOPO_ORDER; do
  PKG_DIR=$(echo "$PKG" | cut -d/ -f2)
  DEPS=$(jq -r '.dependencies // {} | keys[]' "packages/$PKG_DIR/package.json" 2>/dev/null | grep '^@gardenfi/' || true)
  for DEP in $DEPS; do
    REVERSE_DEP_MAP[$DEP]="${REVERSE_DEP_MAP[$DEP]} $PKG"
  done
done

# Resolve full publish list (including dependents)
declare -A SHOULD_PUBLISH
queue=()
for CHG in $CHANGED; do
  SHOULD_PUBLISH[$CHG]=1
  queue+=("$CHG")
done

while [[ ${#queue[@]} -gt 0 ]]; do
  CURRENT=${queue[0]}
  queue=("${queue[@]:1}")
  for DEP in ${REVERSE_DEP_MAP[$CURRENT]}; do
    [[ -z "${SHOULD_PUBLISH[$DEP]}" ]] && SHOULD_PUBLISH[$DEP]=1 && queue+=("$DEP")
  done
done

PUBLISH_ORDER=()
for PKG in $TOPO_ORDER; do
  [[ ${SHOULD_PUBLISH[$PKG]} == 1 ]] && PUBLISH_ORDER+=("$PKG")
done

# Helper: version bump
increment_version() {
  local VERSION=$1 TYPE=$2
  IFS='.' read -r MAJOR MINOR PATCH <<< "${VERSION%%-*}"
  case $TYPE in
    major) ((MAJOR++)); MINOR=0; PATCH=0 ;;
    minor) ((MINOR++)); PATCH=0 ;;
    patch) ((PATCH++)) ;;
    prerelease)
      [[ $VERSION =~ -beta\.[0-9]+$ ]] && NUM=$(( ${VERSION##*-beta.} + 1 )) || NUM=0
      echo "${MAJOR}.${MINOR}.${PATCH}-beta.$NUM"
      return ;;
    *) echo "Invalid bump type"; exit 1 ;;
  esac
  echo "$MAJOR.$MINOR.$PATCH"
}
export -f increment_version

# Publish loop
for PKG in "${PUBLISH_ORDER[@]}"; do
  echo -e "\n📦 Processing $PKG"
  DIR="${PKG_NAME_TO_DIR[$PKG]}"
  cd "packages/$DIR"

  PACKAGE_NAME=$(jq -r .name package.json)
  CURRENT_VERSION=$(npm view $PACKAGE_NAME version 2>/dev/null || jq -r .version package.json)

  echo "Current version: $CURRENT_VERSION"

  if [[ "$VERSION_BUMP" == "prerelease" ]]; then
    LATEST_BETA=$(npm view $PACKAGE_NAME versions --json | jq -r '[.[] | select(contains("-beta"))] | max // empty')
    NEW_VERSION=${LATEST_BETA:+${CURRENT_VERSION%-beta.*}-beta.$(( ${LATEST_BETA##*-beta.} + 1 ))}
    [[ -z "$LATEST_BETA" ]] && NEW_VERSION="${CURRENT_VERSION}-beta.0"
  else
    NEW_VERSION=$(increment_version "$CURRENT_VERSION" "$VERSION_BUMP")
  fi

  echo "New version: $NEW_VERSION"
  jq --arg v "$NEW_VERSION" '.version = $v' package.json > tmp.json && mv tmp.json package.json

  yarn build

  if [[ "$VERSION_BUMP" == "prerelease" ]]; then
    npm publish --tag beta --access public
  else
    if [[ "$IS_PR" != "true" ]]; then
      git add package.json
      git -c user.email="$COMMIT_EMAIL" -c user.name="$COMMIT_NAME" commit -m "V$NEW_VERSION"
      npm publish --access public
      git tag "$PACKAGE_NAME@$NEW_VERSION"
      git push https://x-access-token:${GH_PAT}@github.com/catalogfi/garden.js.git HEAD:main --tags
    else
      echo "Skipping commit in PR context."
    fi
  fi

  cd - > /dev/null
done

# Cleanup and final commit (if needed)
yarn config unset yarnPath
jq 'del(.packageManager)' package.json > temp.json && mv temp.json package.json

if [[ "$IS_PR" != "true" && -n $(git status --porcelain) ]]; then
  git add .
  git -c user.email="$COMMIT_EMAIL" -c user.name="$COMMIT_NAME" commit -m "commit release script and config changes"
  git push https://x-access-token:${GH_PAT}@github.com/catalogfi/garden.js.git HEAD:main
fi

rm -f ~/.npmrc
