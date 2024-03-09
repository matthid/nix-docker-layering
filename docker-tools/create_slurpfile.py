import os
import sys
import json

def get_total_size(start_path):
    total_size = 0
    for dirpath, dirnames, filenames in os.walk(start_path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            # skip if it is symbolic link
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)
    sys.stderr.write(f"Size of {start_path} -> {total_size}.\n")
    return total_size


def split_to_layers(file_sizes, max_layers):
    # Calculate the maximum size per layer
    total_size = sum(file_sizes.values())
    max_layer_size = total_size // max_layers

    sys.stderr.write(f"Using size {max_layer_size} ({total_size} / {max_layers}).\n")

    layers = []
    layer_contents = []
    layer_size = 0

    # Accumulate file paths in a layer until the total size exceeds the maximum size per layer
    for path, file_size in file_sizes.items():
        # Always add the current
        layer_contents.append(path)
        layer_size += file_size
        if len(layers) < max_layers and layer_size > max_layer_size and layer_contents:
            sys.stderr.write(f"Adding layer {len(layers)} with size {layer_size} and {len(layer_contents)} elements.\n")
            layers.append(layer_contents)
            layer_contents = []
            layer_size = 0


    # Add remaining files to the last layer
    if layer_contents:
        sys.stderr.write(f"Adding (last) layer {len(layers)} with size {layer_size}.\n")
        layers.append(layer_contents)

    return layers


def main():
    with open(sys.argv[1], 'r') as file:
        paths = file.read().splitlines()

    # Calculate sizes once and store it in dictionary
    file_sizes = {path: get_total_size(path) for path in paths}

    max_layers = int(sys.argv[2])
    layers = split_to_layers(file_sizes, max_layers)

    print(json.dumps(layers))


if __name__ == '__main__':
    main()
