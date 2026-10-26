"""Minimal adapter skeleton. Implement your provider's documented, authorised API here."""
import json
import os
from pathlib import Path
import sys


def formula(image_path, api_key):
    # Return recognised LaTeX from the selected image. Never log credentials.
    raise NotImplementedError('Configure your OCR implementation')


def pdf(source_path, output_directory, output_format, api_key):
    # Write result.md or result.tex here, with optional relative assets/ files.
    raise NotImplementedError('Configure your PDF implementation')


def main():
    request = json.load(sys.stdin)
    response = {'schema': 1, 'id': request['id'], 'ok': True}
    try:
        if request['schema'] != 1:
            raise ValueError('Unsupported protocol')
        operation = request['operation']
        api_key = os.environ.get('BAKER_PLUGIN_API_KEY')
        if operation == 'probe':
            # Replace this with a non-billable readiness check; never upload a document.
            response['ok'] = False  # Change after implementing this adapter.
        elif operation == 'configure':
            # Add configuration: true after implementing your authenticate/save callbacks.
            # Load setup.py from Path(__file__).parent and call setup.run(store, authenticate).
            response['ok'] = False
        elif operation == 'formula':
            response['latex'] = formula(Path(request['input']['path']), api_key)
        elif operation == 'pdf':
            output = request['output']
            response['output'] = pdf(Path(request['input']['path']), Path(output['directory']), output['format'], api_key)
        else:
            raise ValueError('Unsupported operation')
    except Exception:
        response = {'schema': 1, 'id': request['id'], 'ok': False}
    print(json.dumps(response))


if __name__ == '__main__':
    main()
