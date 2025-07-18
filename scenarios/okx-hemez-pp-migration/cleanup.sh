#!/usr/bin/env bash
set -euo pipefail

# cleanup.sh: Provides options for full cleanup or soft reset of the agglayer environment.

echo "Select cleanup mode:"
echo "1) Full Cleanup (stop all services and remove state)"
echo "2) Soft Reset    (stop nodes, preserve anvil and state)"
echo "3) Exit"

read -rp "Enter choice [1-3]: " choice
\case "$choice" in
  1)
    echo "Performing Full Cleanup..."
    docker stop agglayer-node || true
    docker stop agglayer-prover || true
    docker stop anvil || true
    echo "Optionally remove temporary directory:"
    read -rp "Remove \$tdir and all contents? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      if [[ -n "${tdir:-}" && -d "$tdir" ]]; then
        rm -rf "$tdir"
        echo "Removed \$tdir"
      else
        echo "No valid \$tdir to remove"
      fi
    fi
    ;;

  2)
    echo "Performing Soft Reset..."
    docker stop agglayer-node || true
    docker stop agglayer-prover || true
    # preserve anvil
    if [[ -z "${tdir:-}" ]]; then
      echo "Error: tdir must be set for soft reset." >&2
      exit 1
    fi
    echo "Cleaning agglayer state and SQL data..."
    sudo rm -rf "$tdir/agglayer"/*
    sudo rm -f "$tdir/aggkit/aggsender.sql*"
    sudo rm -f "$tdir/aggkit/reorgdetectorl*"
    echo "Block-level soft reset SQL statements (manual):"
    cat << 'EOF'
-- Connect to SQLite and run:
delete from l1_info_root where block_num > 22688021;
delete from block where num > 22688021;
delete from l1info_leaf where block_num > 22688021;
delete from verify_batches where block_num > 22688021;
delete from l1info_initial where block_num > 22688021;
EOF
    ;;

  3)
    echo "Exiting without changes."
    exit 0
    ;;

  *)
    echo "Invalid choice: $choice" >&2
    exit 1
    ;;
esac

echo "Cleanup complete."

