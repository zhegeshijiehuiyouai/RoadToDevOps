#!/usr/bin/env python3
# 找出jar文件和class目录中的重复类。用于排查Java类冲突问题。

# -*- coding: utf-8 -*-
# @Function
# Find duplicate classes among java lib dirs and class dirs.
#
# @Usage
#   $ show-duplicate-java-classes # search jars from current dir
#   $ show-duplicate-java-classes path/to/lib_dir1 /path/to/lib_dir2
#   $ show-duplicate-java-classes -c path/to/class_dir1 -c /path/to/class_dir2
#   $ show-duplicate-java-classes -c path/to/class_dir1 path/to/lib_dir1
#   $ show-duplicate-java-classes -L path/to/lib_dir1 # search jars in the sub-directories of lib dir
#   $ show-duplicate-java-classes -J path/to/lib_dir1 # search jars in the jar file
#
# @online-doc https://github.com/oldratlee/useful-scripts/blob/dev-2.x/docs/java.md#-show-duplicate-java-classes
# @author tg123 (farmer1992 at gmail dot com)
# @author Jerry Lee (oldratlee at gmail dot com)

__author__ = 'tg123'

import os
import re
import sys
from glob import glob
from io import BytesIO
from optparse import OptionParser
from os import walk
from os.path import relpath, isdir, exists
from zipfile import ZipFile, BadZipfile

################################################################################
# utils functions
################################################################################
PROG_VERSION = '2.4.0-dev'

# How to delete line with echo?
# https://unix.stackexchange.com/questions/26576
#
# terminal escapes: http://ascii-table.com/ansi-escape-sequences.php
# In particular, to clear from the cursor position to the beginning of the line:
# echo -e "\033[1K"
# Or everything on the line, regardless of cursor position:
# echo -e "\033[2K"
__clear_line = '\033[2K\r'
__show_responsive = True


def __get_terminal_columns_of_stderr():
    """
    Rewritten for stderr from <shutil.get_terminal_size>
    """
    try:
        columns, _ = os.get_terminal_size(sys.stderr.fileno())
    except (AttributeError, ValueError, OSError):
        columns = 0

    return columns


def print_responsive_message(msg):
    if not __show_responsive or not sys.stderr.isatty():
        return
    columns = __get_terminal_columns_of_stderr()
    if columns <= 0:
        return

    print(__clear_line + msg[:columns], end='', file=sys.stderr)


def clear_responsive_message():
    if not __show_responsive or not sys.stderr.isatty():
        return
    print(__clear_line, end='', file=sys.stderr)


def print_error(msg):
    clear_responsive_message()
    print(msg, file=sys.stderr)


def print_box_message(msg):
    print()
    print('=' * 80)
    print(msg)
    print('=' * 80)


def list_jar_file_under_lib_dirs(lib_dirs, recursive):
    jar_files = set()

    idx_str_max_len = len(str(len(lib_dirs)))
    for idx, lib_dir in enumerate(lib_dirs, start=1):
        print_responsive_message('list jar file under lib dir(%*s/%s): %s' % (
            idx_str_max_len, idx, len(lib_dirs), lib_dir))

        if not exists(lib_dir):
            print_error('WARN: lib dir %s not exists, ignored!' % lib_dir)
            continue

        if not isdir(lib_dir):
            jar_files.add(lib_dir)
            continue

        if not recursive:
            jar_files |= {p for p in glob(lib_dir + '/*.jar')}
            continue

        jar_files |= {
            dir_path + '/' + filename
            for dir_path, _, file_names in walk(lib_dir)
            for filename in file_names if filename.lower().endswith('.jar')
        }

    return jar_files


def list_class_under_jar_file(jar_file, recursive, progress):
    """
    :return: map: jar_jar_path('a.jar!b.jar!c.jar') -> classes
    """
    index = 0

    def list_zip_in_zip(jar_jar_path, zf):
        nonlocal index
        index += 1
        index_marker = ''
        if recursive:
            index_marker = ' #%3s' % index
        print_responsive_message('list class under jar file(%*s/%s%s): %s' % (
            len(str(progress[1])), progress[0], progress[1], index_marker, jar_jar_path))

        ret = {}
        classes = {f for f in zf.namelist() if f.lower().endswith('.class')}
        ret[jar_jar_path] = classes
        if not recursive:
            return ret

        jars_in_jar = {f for f in zf.namelist() if f.lower().endswith('.jar')}
        for jar in jars_in_jar:
            next_jar_jar_path = jar_jar_path + '!' + jar
            try:
                with ZipFile(BytesIO(zf.read(jar))) as f:
                    ret.update(list_zip_in_zip(next_jar_jar_path, f))
            except BadZipfile as e:
                print_error('WARN: %s is bad zip file(%s), ignored!' % (next_jar_jar_path, e))

        return ret

    try:
        with ZipFile(jar_file) as zip_file:
            return list_zip_in_zip(jar_file, zip_file)
    except BadZipfile as error:
        print_error('WARN: %s is bad zip file(%s), ignored!' % (jar_file, error))
        return {}


def list_class_under_class_dir(class_dir, progress):
    print_responsive_message('list class under class dir(%*s/%s): %s' % (
        len(str(progress[1])), progress[0], progress[1], class_dir))

    if not exists(class_dir):
        print_error('WARN: class dir %s not exists, ignored!' % class_dir)
        return {}
    if not isdir(class_dir):
        print_error('WARN: class dir %s is not dir, ignored!' % class_dir)
        return {}

    return {relpath(dir_path + '/' + filename, class_dir)
            for dir_path, _, file_names in walk(class_dir)
            for filename in file_names if filename.lower().endswith('.class')}


def collect_class_path_to_classes(jar_files, class_dirs, recursive_jar):
    class_path_to_classes = {}
    total_count = len(jar_files) + len(class_dirs)
    index = 0

    # list all classes in jar files
    for jar_file in jar_files:
        index += 1
        class_path_to_classes.update(
            list_class_under_jar_file(jar_file, recursive=recursive_jar, progress=(index, total_count)))
    # list all classes in class dirs
    for class_dir in class_dirs:
        index += 1
        class_path_to_classes[class_dir] = list_class_under_class_dir(class_dir, progress=(index, total_count))
    return class_path_to_classes


def invert_as_class_to_class_paths(class_path_to_classes):
    class_to_class_paths = {}
    for class_path, classes in class_path_to_classes.items():
        for clazz in classes:
            class_to_class_paths.setdefault(clazz, set()).add(class_path)
    return class_to_class_paths


################################################################################
# biz functions
################################################################################

__java9_module_file_pattern = re.compile(r'(^|.*/)module-info\.class$')


def find_duplicate_classes(class_to_class_paths):
    class_paths_to_duplicate_classes = {}

    for clazz, class_paths in class_to_class_paths.items():
        # skip java 9 module-info files
        if len(class_paths) == 1 or __java9_module_file_pattern.match(clazz):
            continue

        classes = class_paths_to_duplicate_classes.setdefault(frozenset(class_paths), set())
        classes.add(clazz)

    return class_paths_to_duplicate_classes


def print_duplicate_classes_info(class_paths_to_duplicate_classes):
    if not class_paths_to_duplicate_classes:
        print('COOL! No duplicate classes found!')
        return

    duplicate_classes_total_count = sum(len(dcs) for dcs in class_paths_to_duplicate_classes.values())
    class_paths_total_count = sum(len(cps) for cps in class_paths_to_duplicate_classes)
    print('Found %s duplicate classes in %s class paths and %s class path sets:' % (
        duplicate_classes_total_count, class_paths_total_count, len(class_paths_to_duplicate_classes)))

    # sort key(class_paths) and value(duplicate_classes)
    class_paths_to_duplicate_classes = [(sorted(cps), sorted(dcs))
                                        for cps, dcs in class_paths_to_duplicate_classes.items()]
    # sort kv pairs
    #
    # sort by multiple keys:
    #    1. class paths count, *descending*; aka. sort by len(item[0]) *reverse=True*
    #    2. duplicate classes count, *descending*; aka. sort by len(item[1]) *reverse=True*
    #    3. class paths, ascending; aka. sort by item[0]
    # sort also ensure output consistent for same input.
    #
    # How to sort objects by multiple keys in Python?
    # https://stackoverflow.com/questions/1143671
    # Sort a list by multiple attributes?
    # https://stackoverflow.com/questions/4233476
    #
    # use - operator of number key for reverse sort key
    class_paths_to_duplicate_classes.sort(key=lambda item: (-len(item[0]), -len(item[1]), item[0]))

    idx_str_max_len = len(str(len(class_paths_to_duplicate_classes)))
    for idx, (class_paths, classes) in enumerate(class_paths_to_duplicate_classes, start=1):
        print('[%*s] found %s duplicate classes in %s class paths:' % (
            idx_str_max_len, idx, len(classes), len(class_paths)))

        class_path_idx_str_max_len = len(str(len(class_paths)))
        for i, cp in enumerate(class_paths, start=1):
            print('    %*s: %s' % (class_path_idx_str_max_len, i, cp))

    print_box_message('Duplicate classes detail info:')
    for idx, (class_paths, classes) in enumerate(class_paths_to_duplicate_classes, start=1):
        print('[%*s] found %s duplicate classes in %s class paths %s :' % (
            idx_str_max_len, idx,
            len(classes), len(class_paths), ' '.join(class_paths)))

        class_idx_str_max_len = len(str(len(classes)))
        for i, c in enumerate(classes, start=1):
            print('    %*s: %s' % (class_idx_str_max_len, i, c))


def print_class_paths_info(class_paths):
    class_paths = sorted(class_paths)

    print_box_message('Find in %s class paths:' % len(class_paths))

    idx_str_max_len = len(str(len(class_paths)))
    for idx, class_path in enumerate(class_paths, start=1):
        print('%*s: %s' % (idx_str_max_len, idx, class_path))


def main():
    option_parser = OptionParser(
        usage='%prog [OPTION]...'
              ' [-c class-dir1 [-c class-dir2] ...]'
              ' [lib-dir1|jar-file1 [lib-dir2|jar-file2] ...]'
              '\nFind duplicate classes among java lib dirs and class dirs.'
              '\n\nExamples:'
              '\n  %prog  # search jars from current dir'
              '\n  %prog path/to/lib_dir1 /path/to/lib_dir2'
              '\n  %prog -c path/to/class_dir1 -c /path/to/class_dir2'
              '\n  %prog -c path/to/class_dir1 path/to/lib_dir1'
              '\n  %prog -L path/to/lib_dir1'
              '\n  %prog -J path/to/lib_dir1',
        version='%prog ' + PROG_VERSION)
    option_parser.add_option('-L', '--recursive-lib', dest='recursive_lib', default=False,
                             action='store_true', help='search jars in the sub-directories of lib dir')
    option_parser.add_option('-J', '--recursive-jar', dest='recursive_jar', default=False,
                             action='store_true', help='search jars in the jar file')
    option_parser.add_option('-c', '--class-dir', dest='class_dirs', default=[],
                             action='append', help='add class dir')
    option_parser.add_option('-R', '--no-find-progress', dest='show_responsive', default=True,
                             action='store_false', help='do not display responsive find progress')
    options, lib_dirs = option_parser.parse_args()
    global __show_responsive
    __show_responsive = options.show_responsive
    if not options.class_dirs and not lib_dirs:
        lib_dirs = ['.']

    class_path_to_classes = collect_class_path_to_classes(
        list_jar_file_under_lib_dirs(lib_dirs, recursive=options.recursive_lib),
        options.class_dirs, recursive_jar=options.recursive_jar)

    print_responsive_message('find duplicate classes...')
    class_to_class_paths = invert_as_class_to_class_paths(class_path_to_classes)
    class_paths_to_duplicate_classes = find_duplicate_classes(class_to_class_paths)

    clear_responsive_message()
    print_duplicate_classes_info(class_paths_to_duplicate_classes)
    print_class_paths_info(class_path_to_classes.keys())

    return int(bool(class_paths_to_duplicate_classes))


if __name__ == '__main__':
    exit(main())
