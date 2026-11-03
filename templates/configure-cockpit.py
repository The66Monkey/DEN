#!/usr/bin/env python3
import configparser
from pathlib import Path
import sys

source, domain = sys.argv[1:]
config = configparser.ConfigParser(interpolation=None)
config.optionxform = str
if Path(source).is_file():
    with open(source) as file:
        config.read_file(file)
if not config.has_section("WebService"):
    config.add_section("WebService")
config["WebService"]["Origins"] = f"https://server.{domain}"
config["WebService"]["ProtocolHeader"] = "X-Forwarded-Proto"
config["WebService"]["ForwardedForHeader"] = "X-Forwarded-For"
config["WebService"]["AllowUnencrypted"] = "false"
config.write(sys.stdout)
