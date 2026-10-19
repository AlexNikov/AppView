#!/bin/bash

# Path to the built binary product
build_path=$1
# Target method name; DanceUI mainly uses View.body or ViewModifier.body(content:)
subprogram_name=$3

root_path="$(dirname "$0")"
echo $root_path

process_string() {
    local original="$1"
    # Remove "<>" and everything inside them
    local step1=$(
        echo $original | \
        perl -p -e 's/(<([^<>]|(?1))*>)*//g'
    )
    # Keep only the first word inside parentheses, then strip parentheses
    local step2=$(echo "$step1" | sed -E 's/([^ ]+)[^)]*/\1/g')
    # Drop parentheses and their contents when the word is "unknown"
    local cleanType=$(echo "$step2" | sed -e 's/(//g' -e 's/)//g' -e 's/unknown//g')

    local -a arr=()

    # Split cleanType on "." and skip empty segments
    for word in ${cleanType//./ }; do
        if [[ -n $word ]]; then
            arr+=("$word")
        fi
    done

    # Print array elements
    echo "${arr[@]}"
}

# Type-name normalization for symbol lookup:
# DanceUIApp.ContentView.(unknown context at $10628778c).TestTypeView<Int> -> [DanceUIApp, ContentView, TestTypeView]
# Final type name: TestTypeView
read -a structure_name_array <<< "$(process_string "$2")"
echo "${structure_name_array[@]}"
last_index=$(( ${#structure_name_array[@]}-1 ))
structure_name=${structure_name_array[$last_index]}
echo $structure_name

# Binary file timestamp used as a unique identifier
file_creation_time=$(stat -f "%B" "${build_path}")
echo $file_creation_time

# Project / binary name
filename=$(basename "$build_path")
echo $filename

file_path="${root_path}/temp/${filename}"
dir_path="$file_path/${file_creation_time}"

# Create directory: /temp/DanceUIApp/1702555003/
if [ -d ${file_path} ]; then
    if [ ! -d ${dir_path} ]; then
        rm -r ${file_path}
        mkdir -p $dir_path
    fi
else
    mkdir -p $dir_path
fi

dsym_file_name="${dir_path}/DanceUIViewDebug_${filename}_${file_creation_time}.dSYM"
echo $dsym_file_name

# Ensure dSYM exists: /temp/DanceUIApp/1702555003/DanceUIViewDebug_DanceUIApp_1702555003.dSYM
if [ -d ${dsym_file_name} ]; then
    echo "File ${dsym_file_name} exists."
else
    # dsymutil generates a dSYM from the binary for source-level debug info
    dsymutil ${build_path} -o ${dsym_file_name}
    echo "File ${dsym_file_name} does not exist."
fi

result_path="${dir_path}/$structure_name.txt"

# Ensure symbol lookup output exists: /temp/DanceUIApp/1702555003/xxx.txt
if [ ! -f ${result_path} ]; then
    # dwarfdump reads debug info from the dSYM
    dwarfdump --name $structure_name ${dsym_file_name} -c > ${result_path}
fi

# Locate source for type method, e.g. ContentView.body

found_contentview=false
in_bodyget=false
linkage_type_name_match=false
declare -a result
while IFS= read -r line; do

    # Match type name: DW_AT_name ("ContentView")
    if [[ "$line" == *"DW_AT_name"* ]]; then
        if [[ $line == *"${structure_name}"* ]]; then
            echo $line
            found_contentview=true
        fi
    fi
  
    # Match method symbol: DW_AT_linkage_name ("$s10DanceUIApp11ContentViewV4bodyQrvg")
    if $found_contentview && [[ "$line" == *"DW_AT_linkage_name"* ]]; then
        echo $line
        all_in_str=true
        for item in "${structure_name_array[@]}"; do
            if [[ $line != *$item* ]]; then
                all_in_str=false
                break
            fi
        done

        if [ "$all_in_str" = true ]; then
            linkage_type_name_match=true
            echo $line
        fi
    fi

    # Match method name: DW_AT_name ("body.get")
    if $found_contentview && [[ "$line" == *"DW_AT_name"* ]]; then
        if [[ $line == *"${subprogram_name}"* ]]; then
            echo $line
            in_bodyget=true
        fi
    fi

    # Source file path: DW_AT_decl_file ("/path/to/ContentView.swift")
    if $in_bodyget && $linkage_type_name_match && [[ "$line" == *"DW_AT_decl_file"* ]]; then
        file=$(echo "$line" | cut -d '"' -f 2)  # Extract file name from the line
        echo $line
        result[0]=$file
    fi

    # Source line number: DW_AT_decl_line (6)
    if $in_bodyget && $linkage_type_name_match && [[ "$line" == *"DW_AT_decl_line"* ]]; then
        line_number=$(echo "$line" | sed 's/[^0-9]*//g')  # Extract line number from the line
        echo $line
        result[1]=$line_number
        break
    fi
done < ${result_path}

# Open xed editor with file name and line number
if [ ${#result[@]} -eq 2 ]; then
    xed --line ${result[1]} ${result[0]}
else
    echo "Cannot find file name and line number."
fi
