# Germline Small-Variant Annotation and Pathogenicity Classification on NCHC

This repository a VEP-based annotation and point-based in-house ACMG classification workflow for germline small variants — GRCh38.

For the details of this pipeline, please refer to the white paper and hands-on in this repo.

## Create the environment
Use the `utils/environment.yml` file to create a conda environment.
``` bash
bash utils/environment.yml
```
After executing this command, you can choose where to install your conda environment and caches.

## Usage
1. Change the "Customize" section in `config.sh`.
2. Execute `submit.sh`.
    ``` bash
    bash submit.sh
    ```
