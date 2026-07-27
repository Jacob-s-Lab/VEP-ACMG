# Germline Small-Variant Annotation and Pathogenicity Classification on NCHC

This repository a VEP-based annotation and point-based in-house ACMG classification workflow for germline small variants — GRCh38.

For detailed information about this pipeline, please refer to the white paper and hands-on in this repo.

Using the following command to clone this pipeline:
``` bash
git clone https://github.com/leechiehyu/VEP-ACMG.git
```

## Create the environment
Use the `utils/setup_env.sh` file to create a conda environment.
``` bash
bash utils/setup_env.sh
```
After executing this command, you can choose where to install your conda environment and caches.

## Usage
1. Change the "Customize" section in `config.sh`.
2. Execute `submit.sh`.
    ``` bash
    bash submit.sh
    ```
