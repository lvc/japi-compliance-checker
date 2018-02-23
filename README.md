JAPICC 2.4
==========

Java API Compliance Checker (JAPICC) — a tool for checking backward binary and source-level compatibility of a Java library API.

Contents
--------

1. [ About      ](#about)
2. [ Install    ](#install)
3. [ Usage      ](#usage)
4. [ Test suite ](#test-suite)

About
-----

The tool checks classes declarations of old and new versions and analyzes changes that may break compatibility: removed methods, removed class fields, added abstract methods, etc. The tool is intended for developers of software libraries and Linux maintainers who are interested in ensuring backward compatibility.

The Scala language is supported since 1.7 version of the tool.

Java 9 is supported since 2.4 version of the tool.

The tool is a core of the Java API Tracker project: https://abi-laboratory.pro/java/tracker/

Install
-------

    sudo make install prefix=/usr

###### Requires

* JDK or OpenJDK - development files
* Perl 5

Usage
-----

    japi-compliance-checker OLD.jar NEW.jar

###### Java 9

    japi-compliance-checker OLD.jmod NEW.jmod

###### Create API dumps

    japi-compliance-checker -dump LIB.jar -dump-path ./API.dump
    japi-compliance-checker API-0.dump API-1.dump

###### Adv. usage

For advanced usage, see `doc/index.html` or output of `-help` option.

Test suite
----------

The tool is tested properly in the Java API Tracker project, by the community and by the internal test suite:

    japi-compliance-checker -test

There are about 100 basic tests in the test suite.
