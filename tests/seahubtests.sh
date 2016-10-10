#!/bin/bash
: ${PYTHON=python}

: ${SEAHUB_TEST_USERNAME="test@seafiletest.com"}
: ${SEAHUB_TEST_PASSWORD="testtest"}
: ${SEAHUB_TEST_ADMIN_USERNAME="admin@seafiletest.com"}
: ${SEAHUB_TEST_ADMIN_PASSWORD="adminadmin"}
: ${DJANGO_SETTINGS_MODULE="seahub.settings"}

export DJANGO_SETTINGS_MODULE
export SEAHUB_TEST_USERNAME
export SEAHUB_TEST_PASSWORD
export SEAHUB_TEST_ADMIN_USERNAME
export SEAHUB_TEST_ADMIN_PASSWORD

[[ -e /etc/default/seafile-server ]] && . /etc/default/seafile-server

# If you run this script on your local machine, you must set CCNET_CONF_DIR
# and SEAFILE_CONF_DIR like this:
#
#       export CCNET_CONF_DIR=/your/path/to/ccnet
#       export SEAFILE_CONF_DIR=/your/path/to/seafile-data
#

set -e
if [[ ${TRAVIS} != "" ]]; then
    set -x
fi

SEAHUB_TESTSDIR=$(python -c "import os; print os.path.dirname(os.path.realpath('$0'))")
SEAHUB_SRCDIR=$(dirname "${SEAHUB_TESTSDIR}")
local_settings_py=${SEAHUB_SRCDIR}/seahub/local_settings.py

export PYTHONPATH="/usr/local/lib/python2.7/site-packages:/usr/lib/python2.7/site-packages:${SEAHUB_SRCDIR}/thirdpart:${PYTHONPATH}"
cd "$SEAHUB_SRCDIR"
set +x

function init() {
    ###############################
    # create database and two new users: an admin, and a normal user
    ###############################
    $PYTHON ./manage.py syncdb

    # create normal user
    $PYTHON -c "import ccnet; pool = ccnet.ClientPool('${CCNET_CONF_DIR}'); ccnet_threaded_rpc = ccnet.CcnetThreadedRpcClient(pool, req_pool=True); ccnet_threaded_rpc.add_emailuser('${SEAHUB_TEST_USERNAME}', '${SEAHUB_TEST_PASSWORD}', 0, 1);"
    # create admin
    $PYTHON -c "import ccnet; pool = ccnet.ClientPool('${CCNET_CONF_DIR}'); ccnet_threaded_rpc = ccnet.CcnetThreadedRpcClient(pool, req_pool=True); ccnet_threaded_rpc.add_emailuser('${SEAHUB_TEST_ADMIN_USERNAME}', '${SEAHUB_TEST_ADMIN_PASSWORD}', 1, 1);"

    # enlarge anon api throttling settings in settings.py, this is a workaround
    # to make tests pass, otherwise a few tests will be throttlled.
    # TODO: cache api token.
    echo "REST_FRAMEWORK = {'DEFAULT_THROTTLE_RATES': {'ping': '6000/minute', 'anon': '5000/minute', 'user': '3000/minute',},}" >> "${local_settings_py}"
}

function start_seahub() {
    $PYTHON ./manage.py runserver 1>/tmp/seahub.access.log 2>&1 &
    sleep 5
}

function check_phantom_js() {
    if ! which phantomjs >/dev/null; then
        echo "Please install phantomjs first:"
        echo
        echo "  On ubuntu: sudo apt-get install phantomjs"
        echo "  On MacOSX: Download the binary from http://phantomjs.org/download.html"
        exit 1
    fi
}

function run_tests() {
    check_phantom_js
    set +e
    py.test "$@" tests
    rvalue=$?
    if [[ ${TRAVIS} != "" ]]; then
        # On travis-ci, dump seahub logs when test finished
        for logfile in /tmp/seahub*.log; do
            echo -e "\nLog file $logfile:\n"
            cat "${logfile}"
            echo
        done
    fi
    exit $rvalue
}

function run_ui_tests() {
    check_phantom_js
    cd  tests/ui/
    set -x
    py.test "$@"
}

action=$1
shift
case $action in
    "init")
        init
        ;;
    "runserver")
        start_seahub
        ;;
    "test")
        run_tests "$@"
        ;;
    "testui")
        run_ui_tests "$@"
        ;;
    *)
        echo "unknow command \"$1\""
        ;;
esac
