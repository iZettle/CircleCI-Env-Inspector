# Deps:
# nushell =0.74.0
# httpie ^3
# GH CLI ^2.21

let date_cutoff = 2023-01-14

if ($env.CIRCLE_TOKEN == null) {
    echo "Set CIRCLE_TOKEN to a CircleCI personal API key."
    exit 1
}
if ($env.GITHUB_TOKEN == null) {
    echo "Set GITHUB_TOKEN to a GitHub token."
    exit 1
}

let url = "https://circleci.com/api/v2"

mut repos = (
  open izettle.json
  | get 0.iZettle.projects 
  | where ($it.project_keys | length) > 0 
  | sort-by -i name 
  | uniq-by name 
  | select name project_keys
  | where (
    $it.project_keys.created_at != null 
      and (
        $it.project_keys.created_at 
        | into datetime
        | any { |it| $it <= $date_cutoff }
      )
    )
  #| where $it.name == "portal"
)

echo $"Found ($repos | length) projects to fix deploy keys for."

$repos = ($repos | each { |repo|
  $repo 
  | insert github_keys (
    https --check-status -A bearer -a $env.GITHUB_TOKEN $"https://api.github.com/repos/izettle/($repo.name)/keys" 
    | from json 
    | select id title key read_only created_at last_used
    | where ($it.title | str downcase | str contains "circleci") == true
  )
})

for $repo in $repos {
  echo $"Updating `($repo.name)`..."
  # Create new deploy key via CCI
  
  # Delete old deploy keys from CCI
  for $key in $repo.project_keys {
    try {
      https --check-status --quiet DELETE $"circleci.com/api/v2/project/gh/iZettle/($repo.name)/checkout-key/($key.fingerprint)" $"Circle-Token:($env.CIRCLE_TOKEN)"
      echo $"  CircleCI: Deleted ($key.fingerprint)."
    } catch {
      echo $"  CircleCI: Failed to delete ($key.fingerprint)."
    }
  }

  # Delete old deploy keys from CCI
  for $key in $repo.github_keys {
    try {
      https --check-status --quiet -A bearer -a $env.GITHUB_TOKEN DELETE $"api.github.com/repos/iZettle/($repo.name)/keys/($key.id)"
      echo $"  GitHub: Deleted ($key.key)."
    } catch {
      echo $"  GitHub: Failed to delete ($key.key)."
    }
  }

  try {
    let key = (
      https --check-status POST $"circleci.com/api/v2/project/gh/iZettle/($repo.name)/checkout-key" $"Circle-Token:($env.CIRCLE_TOKEN)" type=deploy-key
      | from json
    )
    echo $"  Created new deploy key ($key.fingerprint)."
  } catch {
    echo $"  Failed to create a new deploy key."
  }
}

echo "Done"
