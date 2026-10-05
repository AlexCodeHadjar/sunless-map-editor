"""cli-anything-sunless-map — CLI-Anything harness for the SunLess map editor (PEP 420 namespace package)."""

from setuptools import find_namespace_packages, setup

setup(
    name="cli-anything-sunless-map",
    version="1.0.0",
    description="Agent CLI for the SunLess map editor (Godot 4.7): packs, places, paths, checks, previews, export",
    packages=find_namespace_packages(include=["cli_anything.*"]),
    package_data={"cli_anything.sunless_map": ["skills/*.md", "README.md", "tests/TEST.md"]},
    install_requires=["click>=8.0", "prompt_toolkit>=3.0"],
    extras_require={"test": ["pytest>=7"]},
    entry_points={"console_scripts": ["cli-anything-sunless-map=cli_anything.sunless_map.sunless_map_cli:main"]},
    python_requires=">=3.10",
)
