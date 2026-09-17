# Adds (or replaces) the aggkit aggsender service in the enclave.
#
# Used instead of `kurtosis service add/update` because the CLI cannot declare persistent
# directories and `kurtosis service update` was observed to drop mounts (/data disappeared after
# an update). /data (aggkit PathRWData) is a persistent directory that survives replacements, like
# the persisted data directory the runbook asks operators to keep. Runs as root, like every other
# kurtosis-cdk service, so the mounted files are writable.
#
#   kurtosis run --enclave <enclave> assets/aggkit.star \
#     '{"name":"aggkit-001","image":"ghcr.io/agglayer/aggkit:0.8.1","config_artifact":"aggkit-config-v1","replace":false}'
def run(plan, args):
    if args.get("replace", False):
        plan.remove_service(name=args["name"])
    plan.add_service(
        name=args["name"],
        config=ServiceConfig(
            image=args["image"],
            entrypoint=["/usr/local/bin/aggkit"],
            cmd=["run", "--cfg=/etc/aggkit/config.toml", "--components=aggsender"],
            files={
                "/etc/aggkit": Directory(artifact_names=[args["config_artifact"]]),
                "/data": Directory(persistent_key=args["name"] + "-data"),
            },
            ports={
                "rpc": PortSpec(number=5576, transport_protocol="TCP", application_protocol="http", wait="3m"),
            },
            user=User(uid=0, gid=0),
        ),
    )
