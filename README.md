This script reads a TestSummaries.plist file (as produced by Xcode unit tests)
and prints out XML suitable for parsing by Jenkins's [JUnit plugin][jenkins].

## Why do you need this?

The most popular tools for doing this ([xcpretty][xcp] and [trainer][train]) are
surprisingly bad at the one thing they are supposed to do: generate test reports.

* xcpretty tries to parse Xcode's output as it runs the tests rather than
  parsing the nicely formatted summary file. Because tests can run in parallel
  or output log messages that interrupt the output, this resulted in xcpretty
  missing **25%** of our test results in its report.
* trainer outputs redundant timing summaries. This confuses the Jenkins plugin,
  causing it to report incorrect aggregate test times
* trainer incorrectly groups tests (it doesn't translate test targets into
  packages), so if you organize your tests in Xcode into separate targets that
  all gets wiped away in the report
* trainer depends on [fastlane][fast], which is a massive dependency for such a
  simple task
* Both xcpretty and trainer give up if any tests encountered errors, even if
  other tests were run successfully. Meaning you get no report, rather than a
  partial one

## What does this do better?

* No external dependencies
* Simple to run (one file in, prints to stdout)
* Fast (0.25s for ~540 tests)
* Includes test errors in output
* Nicely organizes separate testing targets

## The code sucks

This script doesn't need to parse general XML. It doesn't need to support every
possible feature that JUnit XML readers support. I want to parse Xcode's
TestSummaries.plist file, _nothing else_. I want an output that the Jenkins
JUnit plugin understands, _nothing more_.

So yeah, I parse XML with regex. Fight me.

[jenkins]: https://plugins.jenkins.io/junit
[xcpretty]: https://github.com/xcpretty/xcpretty/issues?utf8=%E2%9C%93&q=is%3Aissue+is%3Aopen+tests
[trainer]: https://github.com/xcpretty/trainer/issues
[fast]: https://github.com/fastlane/fastlane

