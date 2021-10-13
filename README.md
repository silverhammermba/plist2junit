This provides two scripts that read Xcode unit test output and print out XML
suitable for parsing by Jenkins's [JUnit plugin][jenkins].

* plist2junit, for reading TestSummaries.plist from Xcode <= 10
* xcresult2junit, for reading .xcresult directories from Xcode 11+
* extract\_xccovarchive, for working around [this bug][sonar] if you use
  SonarQube for code coverage

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

* Depends only on standard mac OS utilities (ruby, plutil, xcrun, no gems)
* Simple to run (one file in, prints to stdout)
* Fast
  * plist2junit: 0.22s for ~540 tests
  * xcresult2junit: 1.5s for ~700 tests
* Includes test errors in output
* Nicely organizes separate testing targets

[jenkins]: https://plugins.jenkins.io/junit
[xcp]: https://github.com/xcpretty/xcpretty/issues?utf8=%E2%9C%93&q=is%3Aissue+is%3Aopen+tests
[train]: https://github.com/xcpretty/trainer/issues
[fast]: https://github.com/fastlane/fastlane
[sonar]: https://github.com/SonarSource/sonar-scanning-examples/issues/68
