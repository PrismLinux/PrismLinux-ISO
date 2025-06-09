function fish_prompt
## Simple prompt: PWD (git branch) >
 set -l last_status $status

 ## Current Directory
 set_color blue
 echo -n (prompt_pwd)

 ## Git Branch (if in a git repository)
 if command git rev-parse --is-inside-work-tree >/dev/null 2>&1
  set_color yellow
  ## Use __fish_git_prompt for more features later if needed
  echo -n " ("(command git branch --show-current)")"
 end

 ## Status Indicator (> green, > red on error)
 if test $last_status -eq 0
  set_color normal
 else
  set_color red
 end
 echo -n " > "

 ## Reset color for user input
 set_color normal
end
