#!/bin/bash

function get_aws_key_id_from_server_config() {
   grep aws_access_key_id secretshare-server.json | cut -d\" -f4
   if [ "${?}" -ne 0 ]; then
           echo >&2 "Failed to pull aws_access_key_id out of secretshare-server.json"
           exit 1
   fi
}

function get_aws_secret_from_server_config() {
   grep aws_secret_access_key secretshare-server.json | cut -d\" -f4
   if [ "${?}" -ne 0 ]; then
           echo >&2 "Failed to pull aws_secret_key_id out of secretshare-server.json"
           exit 1
   fi
}

if [ "x$TEST_BUCKET_REGION" == "x" ]; then
    echo 'Set $TEST_BUCKET_REGION to the region of the S3 bucket you will use for this test and re-run.'
    exit 1
fi

if [ "x$TEST_BUCKET" == "x" ]; then
    echo 'Set $TEST_BUCKET to the S3 bucket you will use for this test and re-run.'
    exit 1
fi

if [ "x$CURRENT_OS" == "x" ]; then
    echo 'Set $CURRENT_OS to the OS you are testing on (linux, osx, win) and re-run.'
    exit 1
fi

if [ "x$CURRENT_ARCH" == "x" ]; then
    echo 'Set $CURRENT_ARCH to the OS you are testing on (amd64, etc.) and re-run.'
    exit 1
fi

if [ -z "$PORT" ]; then
    PORT=8080
fi
export SECRETSHARE_KEY="TESTTESTTESTTESTTESTTESTTESTTESTTESTTEST"

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    AWS_ACCESS_KEY_ID=$(get_aws_key_id_from_server_config)
    AWS_SECRET_ACCESS_KEY=$(get_aws_secret_from_server_config)
fi

cat > secretshare-server-test.json <<EOF
{
    "addr": "0.0.0.0",
    "port": $PORT,
    "bucket": "$TEST_BUCKET",
    "bucket_region": "$TEST_BUCKET_REGION",
    "secret_key": "$SECRETSHARE_KEY",
    "aws_access_key_id": "$AWS_ACCESS_KEY_ID",
    "aws_secret_access_key": "$AWS_SECRET_ACCESS_KEY"
}
EOF

killall secretshare-server
./build/$CURRENT_OS-$CURRENT_ARCH/secretshare-server -config secretshare-server-test.json &> test-server.log &
server_pid=$!

if [ "x$server_pid" == "x" ]; then
    echo 'Failed to start server!'
    exit 1
fi

sleep 2

if ! kill -0 $server_pid; then
    echo 'Server died unexpectedly!'
    exit 1
fi

CLIENT="./build/$CURRENT_OS-$CURRENT_ARCH/secretshare --endpoint http://localhost:$PORT --bucket-region $TEST_BUCKET_REGION --bucket $TEST_BUCKET"

version_out=$($CLIENT version)
client_version=$(echo "$version_out" | grep '^Client version' | cut -d ':' -f 2 | cut -c 2-)
client_api_version=$(echo "$version_out" | grep '^Client API version' | cut -d ':' -f 2 | cut -c 2-)
server_version=$(echo "$version_out" | grep '^Server version' | cut -d ':' -f 2 | cut -c 2-)
server_api_version=$(echo "$version_out" | grep '^Server API version' | cut -d ':' -f 2 | cut -c 2-)

if [ "x$client_version" != "x4" ]; then
    kill $server_pid
    echo "Wrong client version: $client_version"
    echo -e $version_out
    echo "FAIL"
    exit 1
fi

if [ "x$client_api_version" != "x3" ]; then
    kill $server_pid
    echo "Wrong client API version: $client_api_version"
    echo -e $version_out
    echo "FAIL"
    exit 1
fi

if [ "x$server_version" != "x3" ]; then
    kill $server_pid
    echo "Wrong server version: $server_version"
    echo -e $version_out
    echo "FAIL"
    exit 1
fi

if [ "x$server_api_version" != "x3" ]; then
    kill $server_pid
    echo "Wrong server API version: $server_api_version"
    echo -e $version_out
    echo "FAIL"
    exit 1
fi

echo -n "This is a test" > test.txt
echo > test-client.log
echo "Output from secretshare send:" >> test-client.log
$CLIENT send test.txt >> test-client.log 2>&1
if [ "x$?" != "x0" ]; then
    kill $server_pid
    echo "Upload failed"
    cat test-client.log
    echo "FAIL"
    exit 1
fi
rm test.txt
key=$(grep '^secretshare receive' test-client.log | cut -d ' ' -f 3)

echo >> test-client.log
echo 'Output from secretshare receive:' >> test-client.log
$CLIENT receive "$key" >> test-client.log 2>&1
kill $server_pid

if [ ! -f test.txt ]; then
    echo "Nothing was received!"
    echo -e "$client_out"
    echo "Key: $key"
    echo "FAIL"
    exit 1
fi

contents=$(cat test.txt)

if [ "x$contents" == "xThis is a test" ]; then
    echo "PASS"
    rm test.txt
    exit 0
fi

echo "FAIL"
exit 1
