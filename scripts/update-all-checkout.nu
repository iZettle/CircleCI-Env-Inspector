# Deps:
# nushell =0.74.0
# httpie ^3
# GH CLI ^2.21

let date_cutoff = 2023-01-05

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
  #| first 5
)

print $"Found ($repos | length) projects to fix deploy keys for."

for --numbered $repo in $repos {
  print $"Updating `($repo.item.name)` \(($repo.index + 1)/($repos | length)\)..."

  let project_keys = (
    https --check-status $"circleci.com/api/v2/project/gh/iZettle/($repo.item.name)/checkout-key" $"Circle-Token:($env.CIRCLE_TOKEN)"
    | from json 
    | get items
    | where ($it | length) > 0
    | where ($it | get -i created_at | into datetime) <= $date_cutoff
  )
  print " Fetched CircleCI SSH keys"

  let github_keys = (
    https --check-status -A bearer -a $env.GITHUB_TOKEN $"https://api.github.com/repos/izettle/($repo.item.name)/keys" 
    | from json 
    | where ($it | length) > 0
    | select id title key read_only created_at last_used
    | where ($it.title | str downcase | str contains "circleci") == true
  )
  print $" Fetched GitHub deploy keys..."

  # Delete old deploy keys from CCI
  for $key in $project_keys {
   try {
     https --check-status --quiet DELETE $"circleci.com/api/v2/project/gh/iZettle/($repo.item.name)/checkout-key/($key.fingerprint)" $"Circle-Token:($env.CIRCLE_TOKEN)"
     print $"  CircleCI: Deleted ($key.fingerprint)."
   } catch {
     print $"  CircleCI: Failed to delete ($key.fingerprint)."
   }
  }

  # Delete old deploy keys from CCI
  for $key in $github_keys {
   try {
     https --check-status --quiet -A bearer -a $env.GITHUB_TOKEN DELETE $"api.github.com/repos/iZettle/($repo.item.name)/keys/($key.id)"
     print $"  GitHub: Deleted ($key.key)."
   } catch { |error|
     print $"  GitHub: Failed to delete ($key)\n($error)."
   }
  }
  
  # Create new deploy key via CCI
  try {
   let key = (
     https --check-status POST $"circleci.com/api/v2/project/gh/iZettle/($repo.item.name)/checkout-key" $"Circle-Token:($env.CIRCLE_TOKEN)" type=deploy-key
     | from json
   )
   print $"  Created new deploy key ($key.fingerprint)."
  } catch {
   print $"  Failed to create a new deploy key."
  }
}

echo "Done"
