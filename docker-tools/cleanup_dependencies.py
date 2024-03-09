import sys
import json
import os

def remove_excluded_dependencies(dependencies, exclude_paths):
    return [dep for dep in dependencies if dep['path'] not in exclude_paths]

def main():
    sys.stderr.write(f"running cleanup_dependencies {repr(sys.argv)}\n")
    json_file = sys.argv[1]
    available_layers = int(sys.argv[2])
    exclude_paths = sys.argv[3:]
    sys.stderr.write(f"Removing dependencies {repr(exclude_paths)}\n")
    with open(json_file, 'r') as f:
        data = json.load(f)

    #for filename in os.listdir('.'):
    #    size = os.path.getsize(filename)
    #    sys.stderr.write(f"Listing dir - {filename}, Size: {size} bytes\n")

    # replace stuff
    temp = data['graph']
    data['graph'] = "... skipped ..."
    sys.stderr.write(f"Got data: {json.dumps(data)}\n")
    data['graph'] = temp
    data['graph'] = remove_excluded_dependencies(data['graph'], exclude_paths)
    data['availableLayers'] = available_layers

    # Print the resulting JSON to stdout
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
