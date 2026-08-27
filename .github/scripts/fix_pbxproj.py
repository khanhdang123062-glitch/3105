import re, uuid, sys

with open('ThreeOneOSFive.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

for fname in ['AppGridView.swift', 'AppHackDetailView.swift']:
    if fname in content:
        print(f'{fname} already registered')
        continue
    ref_id = uuid.uuid4().hex[:24].upper()
    build_id = uuid.uuid4().hex[:24].upper()
    content = content.replace(
        '/* End PBXFileReference section */',
        f'\t\t{ref_id} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = "<group>"; }};\n\t\t/* End PBXFileReference section */'
    )
    content = content.replace(
        '/* End PBXBuildFile section */',
        f'\t\t{build_id} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {fname} */; }};\n\t\t/* End PBXBuildFile section */'
    )
    m = re.search(r'path = views;\s*sourceTree[^;]+;\s*\};', content)
    if m:
        insert = content.rfind('children', 0, m.start())
        paren = content.find('(', insert)
        content = content[:paren+1] + f'\n\t\t\t\t{ref_id} /* {fname} */,' + content[paren+1:]
    m2 = re.search(r'isa = PBXSourcesBuildPhase;.*?files = \(', content, re.DOTALL)
    if m2:
        pos = m2.end()
        content = content[:pos] + f'\n\t\t\t\t{build_id} /* {fname} in Sources */,' + content[pos:]
    print(f'Added {fname}')

with open('ThreeOneOSFive.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)
