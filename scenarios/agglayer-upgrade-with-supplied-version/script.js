// This cript add rollup rpc to agglayer
const { execSync } = require("child_process");


function run(cmd, opts = {}) {
  console.log(`$ ${cmd}`);
  execSync(cmd, { stdio: "inherit", ...opts });
}


try {
const editCmd = `kurtosis service exec cdk agglayer '
set -eu
file=/etc/zkevm/agglayer-config.toml
if ! grep -q "2 = http://cdk-erigon-rpc-002:8123" "$file"; then
    sed -i "/1 = \\"http:\\/\\/cdk-erigon-rpc-001:8123\\"/a 2 = \\"http://cdk-erigon-rpc-002:8123\\"" "$file"
    sed -i "/2 = \\"http:\\/\\/cdk-erigon-rpc-002:8123\\"/a 3 = \\"http://cdk-erigon-rpc-003:8123\\"" "$file"
fi
'`;
  run(editCmd);
} catch (e) {
  console.warn(
    `error updating agglayer toml file`
  );
  process.exit(1);
}

// 5) Restart the agglayer service via Kurtosis
run(`kurtosis service stop cdk agglayer`)
run(`kurtosis service start cdk agglayer`)
console.log("Done.");

