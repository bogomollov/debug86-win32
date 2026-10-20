@echo off
pushd "%~dp0"
python -m unittest discover tests
popd
