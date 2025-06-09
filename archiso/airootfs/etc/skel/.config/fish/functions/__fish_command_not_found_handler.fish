function __fish_command_not_found_handler --on-event fish_command_not_found
  set_color blue
  echo -n "❄  "
  set_color red
  echo -n "$argv[1]"
  set_color normal
  echo " not found"
end
