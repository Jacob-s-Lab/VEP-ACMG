# Germline Small-Variant Annotation and Pathogenicity Classification on NCHC

This repository a VEP-based annotation and point-based in-house ACMG classification workflow for germline small variants — GRCh38.

For detailed information about this pipeline, please refer to the [white paper](https://github.com/Jacob-s-Lab/VEP-ACMG/blob/master/VEP-ACMG_White_Paper_2026.pdf) and hands-on ([Chinese](https://github.com/Jacob-s-Lab/VEP-ACMG/blob/master/VEP-ACMG_Hands-on_CH_2026.pdf) & [English](https://github.com/Jacob-s-Lab/VEP-ACMG/blob/master/VEP-ACMG_Hands-on_EN_2026.pdf)) in this repo.

## Create the environment
Use the `utils/setup_env.sh` file to create a conda environment.
``` bash
cd utils
bash setup_env.sh
```
After executing this command, you can choose where to install your conda environment and caches.

## Usage
1. Change the "Customize" section in `config.sh`.
2. Execute `submit.sh`.
    ``` bash
    bash submit.sh
    ```
