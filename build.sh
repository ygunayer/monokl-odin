#!/usr/bin/env sh

set -e

FLAGS="-out=bin/monokl"
CMD=""

print_usage() {
  echo "Usage: $0 <command> [flags...]"
  echo ""
  echo "Commands:"
  echo "   run            Builds and runs the project"
  echo "   build          Builds the project"
  echo ""
  echo "Optional flags:"
  echo "   --debug, -d    Enables debug mode and disables optimizations"
}

for ARG in "$@"; do
  case $ARG in
    -d|--debug)
      FLAGS="$FLAGS -o:none -debug"
      ;;

    run)
      CMD="run"
      ;;

    build)
      CMD="build"
      ;;
  esac
done

if [ -z "$CMD" ]; then
  print_usage
  exit -1
fi

odin $CMD src $FLAGS
