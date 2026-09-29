#!/usr/bin/env python3
"""Generates RENN.xcodeproj/project.pbxproj deterministically (stable object IDs).

Run from anywhere: `python3 scripts/generate_xcodeproj.py`. Sources are synchronized folders
(RENN/, RENNTests/, RENNUITests/), so adding Swift files needs no regeneration; targets, build settings and
package dependencies are defined here.
"""
import hashlib
def oid(name):
    return hashlib.sha1(("renn-" + name).encode()).hexdigest()[:24].upper()

I = {n: oid(n) for n in [
 "project","mainGroup","productsGroup","configGroup","rennGroup","testsGroup",
 "appTarget","testTarget","appProduct","testProduct",
 "appSources","appFrameworks","appResources","testSources","testFrameworks","testResources",
 "proxy","dependency",
 "projCfgList","appCfgList","testCfgList",
 "projDebug","projRelease","appDebug","appRelease","testDebug","testRelease",
 "xcDebugRef","xcReleaseRef","xcSharedRef","xcTestsRef","xcSecretsExampleRef","infoPlistRef",
 "pkgRef","prodDomain","prodFeatures","prodFakes","bfDomain","bfFeatures","bfFakes","prodStorage","bfStorage",
 "testProdFakes","testBfFakes","testProdDomain","testBfDomain","testProdFeatures","testBfFeatures",
 "uiTarget","uiProduct","uiSources","uiFrameworks","uiResources","uiGroup","uiProxy","uiDependency",
 "uiCfgList","uiDebug","uiRelease","xcUITestsRef",
 "rcPkg","fbPkg","prodRevenueCat","bfRevenueCat","prodAnalytics","bfAnalytics","prodCrashlytics","bfCrashlytics",
]}

# Remote packages (06 C01: pinned stable SDKs; exact versions live in Package.resolved).
REVENUECAT_URL = "https://github.com/RevenueCat/purchases-ios"
REVENUECAT_MIN = "5.91.0"
FIREBASE_URL = "https://github.com/firebase/firebase-ios-sdk"
FIREBASE_MIN = "12.19.2"

common_project = {
 "ALWAYS_SEARCH_USER_PATHS": "NO",
 "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
 "CLANG_ANALYZER_NONNULL": "YES",
 "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
 "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
 "CLANG_ENABLE_MODULES": "YES",
 "CLANG_ENABLE_OBJC_ARC": "YES",
 "CLANG_ENABLE_OBJC_WEAK": "YES",
 "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
 "CLANG_WARN_BOOL_CONVERSION": "YES",
 "CLANG_WARN_COMMA": "YES",
 "CLANG_WARN_CONSTANT_CONVERSION": "YES",
 "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
 "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
 "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
 "CLANG_WARN_EMPTY_BODY": "YES",
 "CLANG_WARN_ENUM_CONVERSION": "YES",
 "CLANG_WARN_INFINITE_RECURSION": "YES",
 "CLANG_WARN_INT_CONVERSION": "YES",
 "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
 "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
 "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
 "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
 "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
 "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
 "CLANG_WARN_STRICT_PROTOTYPES": "YES",
 "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
 "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
 "CLANG_WARN_UNREACHABLE_CODE": "YES",
 "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
 "ENABLE_STRICT_OBJC_MSGSEND": "YES",
 "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
 "GCC_C_LANGUAGE_STANDARD": "gnu17",
 "GCC_NO_COMMON_BLOCKS": "YES",
 "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
 "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
 "GCC_WARN_UNDECLARED_SELECTOR": "YES",
 "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
 "GCC_WARN_UNUSED_FUNCTION": "YES",
 "GCC_WARN_UNUSED_VARIABLE": "YES",
 "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
 "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
 "MTL_FAST_MATH": "YES",
 "SDKROOT": "iphoneos",
 "SWIFT_VERSION": "6.0",
}
proj_debug = dict(common_project, **{
 "COPY_PHASE_STRIP": "NO",
 "DEBUG_INFORMATION_FORMAT": "dwarf",
 "ENABLE_TESTABILITY": "YES",
 "GCC_DYNAMIC_NO_PIC": "NO",
 "GCC_OPTIMIZATION_LEVEL": "0",
 "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
 "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
 "ONLY_ACTIVE_ARCH": "YES",
 "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
 "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
})
proj_release = dict(common_project, **{
 "COPY_PHASE_STRIP": "NO",
 "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
 "ENABLE_NS_ASSERTIONS": "NO",
 "MTL_ENABLE_DEBUG_INFO": "NO",
 "SWIFT_COMPILATION_MODE": "wholemodule",
 "VALIDATE_PRODUCT": "YES",
})

def settings(d, indent="\t\t\t\t"):
    return "".join(f"{indent}{k} = {v};\n" for k, v in sorted(d.items()))

def cfg(idk, name, d, base=None):
    b = f"\t\t\tbaseConfigurationReference = {I[base]} /* {base_names[base]} */;\n" if base else ""
    return (f"\t\t{I[idk]} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n{b}"
            f"\t\t\tbuildSettings = {{\n{settings(d)}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")

base_names = {"xcDebugRef": "RENN.debug.xcconfig", "xcReleaseRef": "RENN.release.xcconfig", "xcTestsRef": "RENNTests.xcconfig",
              "xcUITestsRef": "RENNUITests.xcconfig"}

out = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I['bfDomain']} /* RENNDomain in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodDomain']} /* RENNDomain */; }};
		{I['bfFeatures']} /* RENNFeatures in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodFeatures']} /* RENNFeatures */; }};
		{I['bfFakes']} /* RENNFakes in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodFakes']} /* RENNFakes */; }};
		{I['bfStorage']} /* RENNStorage in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodStorage']} /* RENNStorage */; }};
		{I['bfRevenueCat']} /* RevenueCat in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodRevenueCat']} /* RevenueCat */; }};
		{I['bfAnalytics']} /* FirebaseAnalyticsCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodAnalytics']} /* FirebaseAnalyticsCore */; }};
		{I['bfCrashlytics']} /* FirebaseCrashlytics in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodCrashlytics']} /* FirebaseCrashlytics */; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{I['proxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['appTarget']};
			remoteInfo = RENN;
		}};
		{I['uiProxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['appTarget']};
			remoteInfo = RENN;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		{I['appProduct']} /* RENN.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = RENN.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['testProduct']} /* RENNTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = RENNTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['uiProduct']} /* RENNUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = RENNUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['xcUITestsRef']} /* RENNUITests.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = RENNUITests.xcconfig; sourceTree = "<group>"; }};
		{I['xcSharedRef']} /* RENN.shared.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = RENN.shared.xcconfig; sourceTree = "<group>"; }};
		{I['xcDebugRef']} /* RENN.debug.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = RENN.debug.xcconfig; sourceTree = "<group>"; }};
		{I['xcReleaseRef']} /* RENN.release.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = RENN.release.xcconfig; sourceTree = "<group>"; }};
		{I['xcTestsRef']} /* RENNTests.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = RENNTests.xcconfig; sourceTree = "<group>"; }};
		{I['xcSecretsExampleRef']} /* Secrets.example.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Secrets.example.xcconfig; sourceTree = "<group>"; }};
		{I['infoPlistRef']} /* RENN-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "RENN-Info.plist"; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{I['rennGroup']} /* RENN */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = RENN;
			sourceTree = "<group>";
		}};
		{I['testsGroup']} /* RENNTests */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = RENNTests;
			sourceTree = "<group>";
		}};
		{I['uiGroup']} /* RENNUITests */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = RENNUITests;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{I['appFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['bfDomain']} /* RENNDomain in Frameworks */,
				{I['bfFeatures']} /* RENNFeatures in Frameworks */,
				{I['bfFakes']} /* RENNFakes in Frameworks */,
				{I['bfStorage']} /* RENNStorage in Frameworks */,
				{I['bfRevenueCat']} /* RevenueCat in Frameworks */,
				{I['bfAnalytics']} /* FirebaseAnalyticsCore in Frameworks */,
				{I['bfCrashlytics']} /* FirebaseCrashlytics in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['testFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['uiFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['mainGroup']} = {{
			isa = PBXGroup;
			children = (
				{I['rennGroup']} /* RENN */,
				{I['testsGroup']} /* RENNTests */,
				{I['uiGroup']} /* RENNUITests */,
				{I['configGroup']} /* Config */,
				{I['productsGroup']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['configGroup']} /* Config */ = {{
			isa = PBXGroup;
			children = (
				{I['xcSharedRef']} /* RENN.shared.xcconfig */,
				{I['xcDebugRef']} /* RENN.debug.xcconfig */,
				{I['xcReleaseRef']} /* RENN.release.xcconfig */,
				{I['xcTestsRef']} /* RENNTests.xcconfig */,
				{I['xcUITestsRef']} /* RENNUITests.xcconfig */,
				{I['xcSecretsExampleRef']} /* Secrets.example.xcconfig */,
				{I['infoPlistRef']} /* RENN-Info.plist */,
			);
			path = Config;
			sourceTree = "<group>";
		}};
		{I['productsGroup']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['appProduct']} /* RENN.app */,
				{I['testProduct']} /* RENNTests.xctest */,
				{I['uiProduct']} /* RENNUITests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['appTarget']} /* RENN */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['appCfgList']} /* Build configuration list for PBXNativeTarget "RENN" */;
			buildPhases = (
				{I['appSources']} /* Sources */,
				{I['appFrameworks']} /* Frameworks */,
				{I['appResources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['rennGroup']} /* RENN */,
			);
			name = RENN;
			packageProductDependencies = (
				{I['prodDomain']} /* RENNDomain */,
				{I['prodFeatures']} /* RENNFeatures */,
				{I['prodFakes']} /* RENNFakes */,
				{I['prodStorage']} /* RENNStorage */,
				{I['prodRevenueCat']} /* RevenueCat */,
				{I['prodAnalytics']} /* FirebaseAnalyticsCore */,
				{I['prodCrashlytics']} /* FirebaseCrashlytics */,
			);
			productName = RENN;
			productReference = {I['appProduct']} /* RENN.app */;
			productType = "com.apple.product-type.application";
		}};
		{I['testTarget']} /* RENNTests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['testCfgList']} /* Build configuration list for PBXNativeTarget "RENNTests" */;
			buildPhases = (
				{I['testSources']} /* Sources */,
				{I['testFrameworks']} /* Frameworks */,
				{I['testResources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{I['dependency']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I['testsGroup']} /* RENNTests */,
			);
			name = RENNTests;
			packageProductDependencies = (
			);
			productName = RENNTests;
			productReference = {I['testProduct']} /* RENNTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
		{I['uiTarget']} /* RENNUITests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['uiCfgList']} /* Build configuration list for PBXNativeTarget "RENNUITests" */;
			buildPhases = (
				{I['uiSources']} /* Sources */,
				{I['uiFrameworks']} /* Frameworks */,
				{I['uiResources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{I['uiDependency']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I['uiGroup']} /* RENNUITests */,
			);
			name = RENNUITests;
			packageProductDependencies = (
			);
			productName = RENNUITests;
			productReference = {I['uiProduct']} /* RENNUITests.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{I['appTarget']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
					{I['testTarget']} = {{
						CreatedOnToolsVersion = 16.0;
						TestTargetID = {I['appTarget']};
					}};
					{I['uiTarget']} = {{
						CreatedOnToolsVersion = 16.0;
						TestTargetID = {I['appTarget']};
					}};
				}};
			}};
			buildConfigurationList = {I['projCfgList']} /* Build configuration list for PBXProject "RENN" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				tr,
				es,
				"pt-BR",
				de,
				fr,
				ja,
				ko,
				"zh-Hans",
				ru,
				th,
				vi,
				id,
				Base,
			);
			mainGroup = {I['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{I['pkgRef']} /* XCLocalSwiftPackageReference "Packages/RENNCore" */,
				{I['rcPkg']} /* XCRemoteSwiftPackageReference "purchases-ios" */,
				{I['fbPkg']} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {I['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['appTarget']} /* RENN */,
				{I['testTarget']} /* RENNTests */,
				{I['uiTarget']} /* RENNUITests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{I['appResources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['testResources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['uiResources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I['appSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['testSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['uiSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{I['dependency']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['appTarget']} /* RENN */;
			targetProxy = {I['proxy']} /* PBXContainerItemProxy */;
		}};
		{I['uiDependency']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['appTarget']} /* RENN */;
			targetProxy = {I['uiProxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{cfg('projDebug', 'Debug', proj_debug)}{cfg('projRelease', 'Release', proj_release)}{cfg('appDebug', 'Debug', {}, 'xcDebugRef')}{cfg('appRelease', 'Release', {}, 'xcReleaseRef')}{cfg('testDebug', 'Debug', {}, 'xcTestsRef')}{cfg('testRelease', 'Release', {}, 'xcTestsRef')}{cfg('uiDebug', 'Debug', {}, 'xcUITestsRef')}{cfg('uiRelease', 'Release', {}, 'xcUITestsRef')}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{I['projCfgList']} /* Build configuration list for PBXProject "RENN" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['projDebug']} /* Debug */,
				{I['projRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['appCfgList']} /* Build configuration list for PBXNativeTarget "RENN" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['appDebug']} /* Debug */,
				{I['appRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['testCfgList']} /* Build configuration list for PBXNativeTarget "RENNTests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['testDebug']} /* Debug */,
				{I['testRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['uiCfgList']} /* Build configuration list for PBXNativeTarget "RENNUITests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['uiDebug']} /* Debug */,
				{I['uiRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{I['pkgRef']} /* XCLocalSwiftPackageReference "Packages/RENNCore" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/RENNCore;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCRemoteSwiftPackageReference section */
		{I['rcPkg']} /* XCRemoteSwiftPackageReference "purchases-ios" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "{REVENUECAT_URL}";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = {REVENUECAT_MIN};
			}};
		}};
		{I['fbPkg']} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "{FIREBASE_URL}";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = {FIREBASE_MIN};
			}};
		}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{I['prodDomain']} /* RENNDomain */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I['pkgRef']} /* XCLocalSwiftPackageReference "Packages/RENNCore" */;
			productName = RENNDomain;
		}};
		{I['prodFeatures']} /* RENNFeatures */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I['pkgRef']} /* XCLocalSwiftPackageReference "Packages/RENNCore" */;
			productName = RENNFeatures;
		}};
		{I['prodFakes']} /* RENNFakes */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I['pkgRef']} /* XCLocalSwiftPackageReference "Packages/RENNCore" */;
			productName = RENNFakes;
		}};
		{I['prodStorage']} /* RENNStorage */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I['pkgRef']} /* XCLocalSwiftPackageReference "Packages/RENNCore" */;
			productName = RENNStorage;
		}};
		{I['prodRevenueCat']} /* RevenueCat */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I['rcPkg']} /* XCRemoteSwiftPackageReference "purchases-ios" */;
			productName = RevenueCat;
		}};
		{I['prodAnalytics']} /* FirebaseAnalyticsCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I['fbPkg']} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
			productName = FirebaseAnalyticsCore;
		}};
		{I['prodCrashlytics']} /* FirebaseCrashlytics */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I['fbPkg']} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
			productName = FirebaseCrashlytics;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {I['project']} /* Project object */;
}}
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.makedirs(os.path.join(ROOT, "RENN.xcodeproj/project.xcworkspace/xcshareddata"), exist_ok=True)
os.makedirs(os.path.join(ROOT, "RENN.xcodeproj/xcshareddata/xcschemes"), exist_ok=True)
open(os.path.join(ROOT, "RENN.xcodeproj/project.pbxproj"), "w").write(out)
print(I['appTarget'], I['testTarget'])
