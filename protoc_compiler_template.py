# EASY-INSTALL-ENTRY-SCRIPT: 'grpclib==0.4.1','console_scripts','protoc-gen-python_grpc'
__requires__ = "grpclib==0.4.1"
import re
import sys

from pkg_resources import load_entry_point

if __name__ == "__main__":
    sys.argv[0] = re.sub(r"(-script\.pyw?|\.exe)?$", "", sys.argv[0])
    sys.exit(
        load_entry_point(
            "grpclib==0.4.1", "console_scripts", "protoc-gen-python_grpc"
        )()
    )
