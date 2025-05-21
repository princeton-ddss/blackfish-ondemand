# Blackfish
This is the Open OnDemand application for the Blackfish project at Princeton University. It runs the
Blackfish server on a Della visualization node with minimal resources. Once the server is launched,
users authenticate and interact with the server in their browser via the Blackfish UI.


## Deployment

### Setup
For `STAGE = 'dev', 'share'`:
```shell
# Download OnDemand code
cd $HOME/ondemand/$STAGE && git clone https://github.com/princeton-ddss/blackfish-ondemand.git
cd blackfish-ondemand
git pull
# Download Blackfish code
mkdir src
git clone https://github.com/princeton-ddss/blackfish.git
git clone https://github.com/princeton-ddss/blackfish-ui.git
# Create conda environment
module load anaconda3/2024.6
conda create --prefix $HOME/ondemand/$STAGE/blackfish-ondemand/.venv python=3.12
conda activate $HOME/ondemand/$STAGE/blackfish-ondemand/.venv python=3.12
conda install nodejs
# Install Blackfish
pip install src/blackfish
cd src/blackfish-ui
npx update-browserslist-db@latest
npm install .
```

### Testing
To test changes, simply checkout the new commit and run the application. For example,
```shell
# blackfish
cd $HOME/ondemand/dev/blackfish-ondemand/src/blackfish
git fetch origin
git checkout pri-123-fix-the-thing
git pull origin
module load anconda3/2024.6
pip install src/blackfish
# blackfish-ui
cd $HOME/ondemand/dev/blackfish-ondemand/src/blackfish-ui
git fetch origin
git checkout pri-123-fix-the-thing
git pull origin
module load anconda3/2024.6
npx update-browserslist-db@latest
npm install .
```

### Production
Pushing updates to production involves the same process as above applied to the production directory: pull and install changes to the source code in `$HOME/ondemand/share/blackfish-ondemand`.


## Service Updates
Updating service versions is simple matter of updating the default image version specified in the `Blackfish` source code. Thus, it is the same process as deploying a new version of `blackfish` and ensuring that the new image version is made available in the shared cache directory, `/scratch/gpfs/ddsscloud/.blackfish/images`.

## Model Support
The main requirement to run online inference is sufficient GPU memory. As a rule-of-thumb, the *minimum* memory required for a model is obtained by multiplying the number of parameters (in billions) times the number of bytes per parameter (`dtype / 8`). In practice, you need to budget an additional 5-10 GB for KV caching and keep in mind that default GPU utilization is 90%.  

### Tested Models (vllm/vllm-openai:v0.8.4)
| Model                                        | Pipeline                     | Supported | Chat     | Gated | Reasoning | Memory | GPUs       | Cores | Size  | Dtype | Notes                                                                                          |
|----------------------------------------------|------------------------------|-----------|----------|-------|-----------|--------|------------|-------|-------|-------|------------------------------------------------------------------------------------------------|
| Qwen/QwQ-32B                                 | Text-generation              | ✅        | ✅       |       | ✅        | 16G    |  61.0/160G | 4     | 32.8B | bf16  | See https://docs.vllm.ai/en/stable/features/reasoning_outputs.html for reasoning content.      |
| Qwen/Qwen3-32B                               | Text-generation              | ✅        | ✅       |       | ✅        | 16G    |  64.4/160G | 4     | 32.8B | bf16  | See https://docs.vllm.ai/en/stable/features/reasoning_outputs.html for reasoning content.      |
| Qwen/Qwen2.5-72B                             | Text-generation              | ✅        |          |       |           | 16G    | 144.8/320G | 4     | 72.7B | bf16  | Possible to fit on 2x80B by decreasing `max_model_len` or increasing `gpu_memory_utilization`. |
| Qwen/Qwen2.5-72B-Instruct                    | Text-generation              | ✅        | ✅       |       |           | 16G    | 144.8/320g | 4     | 72.7B | bf16  | Possible to fit on 2x80B by decreasing `max_model_len` or increasing `gpu_memory_utilization`. |
| Qwen/Qwen2.5-32B                             | Text-generation              | ✅        |          |       |           | 16G    |   63.1/80G | 4     | 32.8B | bf16  |                                                                                                |
| Qwen/Qwen2.5-32B-Instruct                    | Text-generation              | ✅        | ✅       |       |           | 16G    |   63.1/80G | 4     | 32.8B | bf16  |                                                                                                |
| google/gemma-3-27b-it                        | Text-generation              | ✅        | ✅       | ✅    |           | 16G    |   54.1/80G | 4     | 27.4B | bf16  |                                                                                                |
| meta-llama/Llama-4-Scout-17B-16E-Instruct    | Text-generation              | ❌        | ✅       | ✅    |           | -      |          - | -     |  109B | bf16  | Supports multimodal inputs. See https://docs.vllm.ai/en/latest/features/multimodal_inputs.html#online-serving. |
| meta-llama/Llama-4-Scout-17B-16E             | Text-generation              | ❌        |          | ✅    |           | -      |          - | -     |  109B | bf16  | Supports multimodal inputs. See https://docs.vllm.ai/en/latest/features/multimodal_inputs.html#online-serving. |
| meta-llama/Llama-3.3-70B-Instruct            | Text-generation              | ✅        | ✅       | ✅    |           | 16G    | 140.4/320G | 4     | 70.6B | bf16  |                                                                                                |
| deepseek-ai/DeepSeek-R1-Distill-Llama-70B    | Text generation              | ✅        | ✅       |       | ✅        | 16G    | 141.2/320G | 4     | 70.6B | bf16  | See https://docs.vllm.ai/en/stable/features/reasoning_outputs.html for reasoning content.      |
| deepseek-ai/DeepSeek-R1-Distill-Qwen-32B     | Text generation              | ✅        | ✅       |       | ✅        | 16G    | 64.6/80G   | 4     | 32.8B | bf16  | See https://docs.vllm.ai/en/stable/features/reasoning_outputs.html for reasoning content.      |
| deepseek-ai/DeepSeek-V2-Lite                 | Text generation              | ✅        |          |       |           | 16G    | 30.5/40G   | 4     | 15.7B | bf16  |                                                                                                |
| deepseek-ai/DeepSeek-V2-Lite-Chat            | Text generation              | ✅        | ✅       |       |           | 16G    | 30.5/40G   | 4     | 15.7B | bf16  |                                                                                                |
| openai/whisper-large-v3                      | Automatic-speech-recognition | ✅        |          |       |           | -      | 3.58/10G   | 1     | 1.54B | f16   |                                                                                                |



<!--
| Qwen/Qwen2.5-Omni-7B                         | Text-generation              | ✅        | ✅       |       |           |        |            |       | 10.7B | f32, bf16 | Supports multimodal inputs. See https://docs.vllm.ai/en/latest/features/multimodal_inputs.html#online-serving. | 
| Qwen/Qwen3-14B                               | Text-generation              | ✅        | ✅       |       |           |        |            |       | 14.8B | bf16  |                                                                                           |
| Qwen/Qwen3-8B                                | Text-generation              | ✅        | ✅       |       |           |        |            |       |  8.2B | bf16  |                                                                                           |
| google/gemma-3-1b-it                         | Text-generation              | ✅        | ✅       | ✅    |           | -      | /20G    | 1     |   1.0B | bf16  | Unknown error attempting to run on MIG. |
| meta-llama/Llama-3.2-1B                      | Text-generation              | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.2-1B-Instruct             | Text-generation              | ✅        | ✅       | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.2-3B                      | Text-generation              | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.2-3B-Instruct             | Text-generation              | ✅        | ✅       | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.1-8B                      | Text generation              | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.1-8B-Instruct             | Text generation              | ✅        | ✅       | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.1-70B                     | Text generation              | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.1-70B-Instruct            | Text generation              | ✅        | ✅       | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Meta-Llama-3-8B                   | Text generation              | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Meta-Llama-3-70B                  | Text generation              | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Meta-Llama-3-8B-Instruct          | Text generation              | ✅        | ✅       | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Meta-Llama-3-70B-Instruct         | Text generation              | ✅        | ✅       | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.2-11B-Vision              | Image-text-to-text           | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.2-11B-Vision-Instruct     | Image-text-to-text           | ✅        | ✅       | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.2-90B-Vision              | Image-text-to-text           | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| meta-llama/Llama-3.2-90B-Vision-Instruct     | Image-text-to-text           | ✅        | ✅       | ✅    |           |        |            |       |       |       |                                                                                           |
| stabilityai/stable-diffusion-3.5-large       | Text-to-image                | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| stabilityai/stable-diffusion-3.5-medium      | Text-to-image                | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| stabilityai/stable-diffusion-3-medium        | Text-to-image                | ✅        |          | ✅    |           |        |            |       |       |       |                                                                                           |
| openai/whisper-base                          | Automatic-speech-recognition | ✅        |          |       |           | -      |    ?/10G   | 1     |   72M | f32   |                                                                                           |
| openai/whisper-small                         | Automatic-speech-recognition | ✅        |          |       |           | -      |  0.6/10G   | 1     |  242M | f32   |                                                                                           |
| openai/whisper-medium                        | Automatic-speech-recognition | ✅        |          |       |           | -      | 1.54/10G   | 1     |  764M | f32   |                                                                                           |
-->
