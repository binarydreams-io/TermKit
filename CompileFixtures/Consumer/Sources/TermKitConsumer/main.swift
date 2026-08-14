import TermKit

struct CounterView: View {
    @State private var count = 0

    var graphBody: [NodeDescriptor] {
        VStack(alignment: .leading, spacing: 1) {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
        }
        .padding(1)
        .graphBody
    }
}

let root = CounterView()
print("TermKit consumer: \(root.graphBody.count) root node")
print(TermKitRelease.version)
