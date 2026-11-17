/// No gzip without dart:io (the web build, where App Control never runs).
List<int> controlGunzip(List<int> bytes) => const [];
