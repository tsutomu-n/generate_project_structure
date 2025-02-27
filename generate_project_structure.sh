#!/usr/bin/env bash

# Windows (PowerShell) かどうかを判定
if ($IsWindows -or $(uname -o 2>/dev/null | grep -q 'Microsoft')) {
  # Windows用の区切り文字
  PATH_SEPARATOR="\\"
  NULL_DEVICE="NUL"
} else {
  # Unix/Linux用の区切り文字
  PATH_SEPARATOR="/"
  NULL_DEVICE="/dev/null"
}

# save to .scripts/update_structure.sh
# best way to use is with tree: `apt install tree` (on Debian/Ubuntu)

# Create the output file with header
echo "# Project Structure" > .cursor/rules/structure.mdc
echo "" >> .cursor/rules/structure.mdc
echo "```" >> .cursor/rules/structure.mdc

# Check if tree command is available
if command -v tree >$NULL_DEVICE 2>&1; then
  # Use tree command for better visualization
  git ls-files --others --exclude-standard --cached | tree --fromfile -a >> .cursor/rules/structure.mdc || { echo "Error: git ls-files failed" >&2; exit 1; }
  echo "Using tree command for structure visualization."
else
  # Fallback to the alternative approach if tree is not available
  echo "Tree command not found. Using fallback approach.  Consider installing it (e.g., 'apt install tree' on Debian/Ubuntu)."

  # 一時ファイルを安全に作成
  files_list=$(mktemp) || { echo "Error: mktemp failed" >&2; exit 1; }
  tree_items=$(mktemp) || { echo "Error: mktemp failed" >&2; exit 1; }
  trap "rm -f '$files_list' '$tree_items'" EXIT  # スクリプト終了時に一時ファイルを削除


  # Get all files from git (respecting .gitignore)
  git ls-files --others --exclude-standard --cached | sort > "$files_list" || { echo "Error: git ls-files failed" >&2; exit 1; }

  # Create a simple tree structure
  echo "." > "$tree_items"

   # Process each file to build the tree
  while read -r file; do
    # Skip directories
    if [[ -d "$file" ]]; then continue; fi

    # Add the file to the tree
    echo "$file" >> "$tree_items"

    # Add all parent directories (Bash パラメータ展開を使用)
    dir="$file"
    while [[ "$dir" != "." ]]; do
      dir="${dir%${PATH_SEPARATOR}*}"  # 末尾の区切り文字とファイル名を削除
      if [[ -z "$dir" ]]; then
          dir="."
      fi
      echo "$dir" >> "$tree_items"
    done
  done < "$files_list"

  # Sort and remove duplicates
  sort -u "$tree_items" > "$files_list" # 一時ファイル名を再利用
  mv "$files_list" "$tree_items"


  # Simple tree drawing approach
  prev_dirs=()

  while read -r item; do
    # Skip the root
    if [[ "$item" == "." ]]; then
      continue
    fi

    # Determine if it's a file or directory
    if [[ -f "$item" ]]; then
      is_dir=0
      name="${item##*${PATH_SEPARATOR}}"  # 最後の区切り文字以降を取得 (basename の代わり)
    else
      is_dir=1
      name="${item##*${PATH_SEPARATOR}}/"
    fi

    # Split path into components
    IFS="$PATH_SEPARATOR" read -ra path_parts <<< "$item"

    # Calculate depth (number of path components minus 1)
    depth=$(( ${#path_parts[@]} - 1 ))

    # Find common prefix with previous path
    common=0
    if [[ ${#prev_dirs[@]} -gt 0 ]]; then
      for ((i=0; i<depth && i<${#prev_dirs[@]}; i++)); do
        if [[ "${path_parts[$i]}" == "${prev_dirs[$i]}" ]]; then
          ((common++))
        else
          break
        fi
      done
    fi

     # Build the prefix (grep の代わりにループで処理)
    prefix=""
    for ((i=0; i<depth; i++)); do
      if [[ $i -lt $common ]]; then
        # Check if this component has more siblings
        has_more=0
        parent_dir="${item%${PATH_SEPARATOR}*}"
         if [[ -z "$parent_dir" ]]; then
            parent_dir="."
        fi

        while read -r next_item; do
          next_item_parent="${next_item%${PATH_SEPARATOR}*}"
          if [[ -z "$next_item_parent" ]]; then
              next_item_parent="."
          fi

          if [[ "$next_item_parent" == "$parent_dir" ]] && [[ "$next_item" > "$item" ]]; then
            has_more=1
            break
          fi
        done < "$tree_items"

        if [[ $has_more -eq 1 ]]; then
          prefix="${prefix}│ "
        else
          prefix="${prefix}  "
        fi
      else
        prefix="${prefix}  "
      fi
    done

     # Determine if this is the last item in its directory (grep の代わりにループで処理)
    is_last=1
    dir="${item%${PATH_SEPARATOR}*}"
     if [[ -z "$dir" ]]; then
        dir="."
    fi
    while read -r next_item; do
       next_item_parent="${next_item%${PATH_SEPARATOR}*}"
        if [[ -z "$next_item_parent" ]]; then
            next_item_parent="."
        fi
      if [[ "$next_item_parent" == "$dir" ]] && [[ "$next_item" > "$item" ]]; then
        is_last=0
        break
      fi
    done < "$tree_items"

    # Choose the connector
    if [[ $is_last -eq 1 ]]; then
      connector="└── "
    else
      connector="├── "
    fi

    # Output the item
    echo "${prefix}${connector}${name}" >> .cursor/rules/structure.mdc

    # Save current path for next iteration
    prev_dirs=("${path_parts[@]}")

  done < "$tree_items"

  # Clean up (trap で処理)
fi

# Close the code block
echo "```" >> .cursor/rules/structure.mdc

echo "Project structure has been updated in .cursor/rules/structure.mdc"
