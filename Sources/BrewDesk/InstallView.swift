import SwiftUI

struct InstallView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("패키지 설치")).font(.largeTitle.bold())
            Text(L("Homebrew에서 패키지를 검색하고 내용을 확인한 뒤 설치하세요.")).foregroundStyle(.secondary)
            HStack {
                TextField(L("패키지 이름 검색"), text: $model.catalogQuery)
                    .onSubmit { Task { await model.searchCatalog() } }
                Picker(L("유형"), selection: $model.catalogKind) {
                    Text(L("전체 유형")).tag(Optional<PackageKind>.none)
                    ForEach(PackageKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }.frame(width: 180).onChange(of: model.catalogKind) { _, _ in model.resetCatalog() }
                Button(L("검색")) { Task { await model.searchCatalog() } }
                    .disabled(model.unavailable || model.catalogLoading || model.environment == nil || model.catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.catalogLoading { ProgressView().controlSize(.small) }
            if let error = model.catalogError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HSplitView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.catalogResults) { entry in
                            Button { Task { await model.inspectCatalog(entry) } } label: {
                                HStack {
                                    Image(systemName: entry.kind.symbol)
                                    Text(entry.token)
                                    Text(entry.kind.title).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    if model.packages.contains(where: { $0.id == entry.id }) { Text(L("설치됨")).foregroundStyle(.secondary) }
                                }.padding(12).frame(maxWidth: .infinity).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.unavailable || model.catalogLoading)
                        }
                        if model.catalogResults.isEmpty && !model.catalogLoading {
                            Text(model.environment == nil ? L("설정에서 Homebrew를 연결하세요.") : model.catalogSearched ? L("검색 결과가 없습니다.") : L("검색할 패키지 이름을 입력하세요.")).foregroundStyle(.secondary).padding()
                        }
                        if model.catalogResults.count == 200 { Text(L("최대 200개 결과입니다. 검색어를 좁혀주세요.")).font(.caption) }
                    }
                }.frame(minWidth: 240)
                ScrollView {
                    if let package = model.catalogPackage {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(package.name).font(.title2.bold())
                            Text(package.kind.title).foregroundStyle(.secondary)
                            Text(package.summary)
                            Text(L("버전: \(package.available)"))
                            Text(L("저장소: \(package.tap)"))
                            Text(L("필요한 패키지")).font(.headline)
                            Text(package.dependencies.isEmpty ? L("없음 / 제공 정보 없음") : package.dependencies.joined(separator: ", "))
                            if let url = URL(string: package.homepage), ["http", "https"].contains(url.scheme ?? "") {
                                Link(L("홈페이지"), destination: url)
                            }
                            let installed = !package.installed.isEmpty || model.packages.contains(where: { $0.id == package.id })
                            Button(installed ? L("이미 설치됨") : L("설치…")) { model.prepareInstall() }
                                .buttonStyle(.borderedProminent).disabled(installed || model.unavailable || model.catalogLoading)
                            Text(L("설치 스크립트와 의존 패키지 설치가 실행될 수 있습니다. 인증은 터미널에서 진행합니다.")).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    } else { Text(L("검색 결과를 선택하면 설치 정보를 확인할 수 있습니다.")).foregroundStyle(.secondary).padding(20) }
                }.frame(minWidth: 300)
            }
        }.padding(24)
    }
}
