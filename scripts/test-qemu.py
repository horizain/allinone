import os
import pathlib
import re
import signal
import subprocess
import time

base = pathlib.Path(os.environ['ALLINONE_ENV_DIR'])
log = base / 'zephyr-onboarding/qemu-verified.log'
with log.open('wb') as output:
    process = subprocess.Popen(
        ['west', 'build', '-d', str(base / 'zephyr-builds/qemu-thread-tests'), '-t', 'run'],
        stdin=subprocess.PIPE, stdout=output, stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        deadline = time.monotonic() + 60
        while process.poll() is None:
            if b'PROJECT EXECUTION SUCCESSFUL' in log.read_bytes():
                process.stdin.write(b'\x01x')
                process.stdin.flush()
                break
            if time.monotonic() > deadline:
                raise RuntimeError('QEMU tests timed out; see ' + str(log))
            time.sleep(0.1)
        result = process.wait(timeout=10)
        text = log.read_text()
        print(text)
        if result:
            raise SystemExit(result)
        summaries = re.findall(r'SUITE PASS .*?: pass = (\d+), fail = (\d+), skip = (\d+)', text)
        assert 'PROJECT EXECUTION SUCCESSFUL' in text and summaries
        assert sum(int(passed) for passed, _, _ in summaries) > 0
        assert all(int(failed) == 0 for _, failed, _ in summaries)
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=10)
