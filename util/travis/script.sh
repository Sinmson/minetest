#!/bin/bash -e
. util/travis/common.sh

needs_compile || exit 0

function perform_lint() {
	echo "Performing LINT..."
	CLANG_FORMAT=clang-format-3.9
	CLANG_FORMAT_WHITELIST="util/travis/clang-format-whitelist.txt"

	if [ "$TRAVIS_EVENT_TYPE" = "pull_request" ]; then
		# Get list of every file modified in this pull request
		files_to_lint="$(git diff --name-only --diff-filter=ACMRTUXB $TRAVIS_COMMIT_RANGE | grep '^src/[^.]*[.]\(cpp\|h\)$' | egrep -v '^src/(gmp|lua|jsoncpp)/' || true)"
	else
		# Check everything for branch pushes
		files_to_lint="$(find src/ -name '*.cpp' -or -name '*.h' | egrep -v '^src/(gmp|lua|jsoncpp)/')"
	fi

	local errorcount=0
	local fail=0
	for f in ${files_to_lint}; do
		d=$(diff -u "$f" <(${CLANG_FORMAT} "$f") || true)

		if ! [ -z "$d" ]; then
			errorcount=$((errorcount+1))

			printf "The file %s is not compliant with the coding style" "$f"
			if [ ${errorcount} -gt 50 ]; then
				printf "\nToo many errors encountered previously, this diff is hidden.\n"
			else
				printf ":\n%s\n" "$d"
			fi

			whitelisted=$(egrep -c "^${f}" "${CLANG_FORMAT_WHITELIST}")

			# If file is not whitelisted, mark a failure
			if [ ${whitelisted} -eq 0 ]; then
				fail=1
			fi
		fi
	done

	if [ "$fail" = 1 ]; then
		echo "LINT reports failure."
		exit 1
	fi

	echo "LINT OK"
}

if [[ "$LINT" == "1" ]]; then
	# Lint with exit CI
	perform_lint
	exit 0
fi

if [[ $PLATFORM == "Unix" ]]; then
	mkdir -p travisbuild
	cd travisbuild || exit 1

	CMAKE_FLAGS=''
	if [[ $COMPILER == "g++-6" ]]; then
		export CC=gcc-6
		export CXX=g++-6
	fi

	# Clang builds with FreeType fail on Travis
	if [[ $CC == "clang" ]]; then
		CMAKE_FLAGS+=' -DENABLE_FREETYPE=FALSE'
	fi

	if [[ $TRAVIS_OS_NAME == "osx" ]]; then
		CMAKE_FLAGS+=' -DCUSTOM_GETTEXT_PATH=/usr/local/opt/gettext'
	fi

	cmake -DCMAKE_BUILD_TYPE=Debug \
		-DRUN_IN_PLACE=TRUE \
		-DENABLE_GETTEXT=TRUE \
		-DBUILD_SERVER=TRUE \
		$CMAKE_FLAGS ..
	make -j2

	echo "Running unit tests."
	CMD="../bin/minetest --run-unittests"
	if [[ "$VALGRIND" == "1" ]]; then
		valgrind --leak-check=full --leak-check-heuristics=all --undef-value-errors=no --error-exitcode=9 ${CMD} && exit 0
	else
		${CMD} && exit 0
	fi

elif [[ $PLATFORM == Win* ]]; then
	[[ $CC == "clang" ]] && exit 1 # Not supposed to happen
	# We need to have our build directory outside of the minetest directory because
	#  CMake will otherwise get very very confused with symlinks and complain that
	#  something is not a subdirectory of something even if it actually is.
	# e.g.:
	# /home/travis/minetest/minetest/travisbuild/minetest
	# \/  \/  \/
	# /home/travis/minetest/minetest/travisbuild/minetest/travisbuild/minetest
	# \/  \/  \/
	# /home/travis/minetest/minetest/travisbuild/minetest/travisbuild/minetest/travisbuild/minetest
	# You get the idea.
	OLDDIR=$(pwd)
	cd ..
	export EXISTING_MINETEST_DIR=$OLDDIR
	export NO_MINETEST_GAME=1
	if [[ $PLATFORM == "Win32" ]]; then
		"$OLDDIR/util/buildbot/buildwin32.sh" travisbuild && exit 0
	elif [[ $PLATFORM == "Win64" ]]; then
		"$OLDDIR/util/buildbot/buildwin64.sh" travisbuild && exit 0
	fi
else
	echo "Unknown platform \"${PLATFORM}\"."
	exit 1
fi

