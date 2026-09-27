#!/bin/bash


erlc *.erl
erl -eval 'server:start().'