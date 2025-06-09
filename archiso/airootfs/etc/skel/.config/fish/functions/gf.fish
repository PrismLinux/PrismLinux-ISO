function gf --description "Git flow helper function"
  set -l cmd $argv[1]
  set -l args $argv[2..-1]

  if test -z "$cmd"
    echo "Git Flow Helper"
    echo "Usage: gf [command] [arguments]"
    echo ""
    echo "Commands:"
    echo "  s, status       Show git status"
    echo "  a, add          Add files: gf a . or gf a file.txt"
    echo "  c, commit       Commit with message: gf c \"commit message\""
    echo "  ca              Commit all changed files: gf ca \"commit message\""
    echo "  p, push         Push to remote"
    echo "  pl, pull        Pull from remote"
    echo "  co, checkout    Checkout branch: gf co branch-name"
    echo "  cb              Create and checkout new branch: gf cb new-branch"
    echo "  b, branch       List branches"
    echo "  m, merge        Merge branch: gf m branch-name"
    echo "  d, diff         Show changes"
    echo "  l, log          Show commit logs"
    echo "  r, reset        Reset files: gf r file.txt or gf r --hard"
    echo "  cl, clean       Clean repository: gf cl"
    echo "  t, tag          Create tag: gf t v1.0.0 or list tags: gf t"
    return 0
  end

  switch $cmd
    case s status
      git status
    case a add
      if test (count $args) -eq 0
        git add .
      else
        git add $args
      end
    case c commit
      if test (count $args) -eq 0
        echo "Error: Commit message required"
        return 1
      end
      git commit -m "$args"
    case ca
      if test (count $args) -eq 0
        echo "Error: Commit message required"
        return 1
      end
      git add .
      git commit -m "$args"
    case p push
      git push $args
    case pl pull
      git pull $args
    case co checkout
      git checkout $args
    case cb
      if test (count $args) -eq 0
        echo "Error: Branch name required"
        return 1
      end
      git checkout -b $args
    case b branch
      git branch $args
    case m merge
      if test (count $args) -eq 0
        echo "Error: Branch name required"
        return 1
      end
      git merge $args
    case d diff
      git diff $args
    case l log
      git log --oneline --graph --decorate $args
    case r reset
      git reset $args
    case cl clean
      git clean -fd $args
    case t tag
      if test (count $args) -eq 0
        git tag
      else
        git tag $args
      end
    case '*'
      echo "Unknown command: $cmd"
      return 1
  end
end
