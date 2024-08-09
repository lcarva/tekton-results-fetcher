#! /bin/env python
import json
import os
import os.path
import sys

HERMETIC_DIR = 'hermetic'

def get_pipelinerun_params(pr):
    """
    This returns a dict of PipelineRun parameters and their values. It takes into account
    parameters from the Pipeline that contain default values.
    """

    params = dict()

    # First get the default parameters from the Pipeline.
    for param in pr.get('spec', {}).get('pipelineSpec', {}).get('params', []):
        default = param.get('default')
        if default is not None:
            params[param['name']] = default

    # Next, get all the PipelineRun parameters.
    for param in pr.get('spec', {}).get('params', []):
        params[param['name']] = param['value']

    return params

def find_pipeline_tasks_param_values(pr, param_name):
    """
    Returns a list of parameter values from the PipelineTasks matching the given name.
    """
    pr_params = get_pipelinerun_params(pr)
    # TODO: Handle finally tasks as well.
    for task in pr.get('spec', {}).get('pipelineSpec', {}).get('tasks', []):
        for param in task.get('params', []):
            if param['name'] == param_name:
                yield resolve_param_value(param['value'], pr_params)

def resolve_param_value(task_value, pr_params):
    """
    Resolves things like '$(params.FOO)' to 'bar' if pr_params is {'FOO': 'bar'}
    """
    for name, value in pr_params.items():
        task_value = task_value.replace(f'$(params.{name})', value)
    return task_value

def is_hermetic(pr):
    for value in find_pipeline_tasks_param_values(pr, 'HERMETIC'):
        if value == 'true':
            return True
    return False

def main():
    os.makedirs(HERMETIC_DIR, exist_ok=True)

    for pr_raw in sys.stdin:
        pr = json.loads(pr_raw)
        uid = pr['metadata']['uid']
        fname = f'{uid}.json'
        if is_hermetic(pr):
            p = os.path.join(HERMETIC_DIR, fname)
            with open(p, mode='w') as f:
                f.write(pr_raw)

if __name__ == '__main__':
    # < pipelineruns.json jq -c '.' | ./classify.py
    main()

