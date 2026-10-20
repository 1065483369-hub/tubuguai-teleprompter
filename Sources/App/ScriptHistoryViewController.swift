import UIKit

/// 历史稿列表：点一条恢复，左滑删除，也可清空全部。
/// 数据只在本机 UserDefaults，不上传、不需要登录。
final class ScriptHistoryViewController: UIViewController {
    private let store: ScriptHistoryStore
    private var items: [ScriptHistoryItem] = []
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let empty = UILabel()
    private let countLabel = UILabel()
    var onSelect: ((String) -> Void)?

    init(store: ScriptHistoryStore = .shared) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.bg
        build()
        reload()
    }

    private func build() {
        let close = UIButton(type: .system)
        close.setTitle("关闭", for: .normal)
        close.setTitleColor(DS.ink2, for: .normal)
        close.titleLabel?.font = DS.font(.body)
        close.accessibilityIdentifier = "historyClose"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let title = UILabel()
        title.text = "历史提示词"
        title.font = DS.font(.body, weight: .bold)
        title.textColor = DS.ink

        let clear = UIButton(type: .system)
        clear.setTitle("清空", for: .normal)
        clear.setTitleColor(UIColor(hex: 0xE85D86), for: .normal)
        clear.titleLabel?.font = DS.font(.body, weight: .semibold)
        clear.accessibilityIdentifier = "historyClear"
        clear.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        let bar = UIView()
        [close, title, clear].forEach { v in
            v.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(v)
        }
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 44),
            close.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            close.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            clear.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        countLabel.font = DS.font(.footnote)
        countLabel.textColor = DS.ink3
        countLabel.numberOfLines = 0

        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = 104
        table.dataSource = self
        table.delegate = self
        table.register(HistoryCell.self, forCellReuseIdentifier: "history")
        table.accessibilityIdentifier = "historyList"

        empty.text = "还没有历史稿\n完成一篇稿子后，会自动保存在这里"
        empty.font = DS.font(.body)
        empty.textColor = DS.ink3
        empty.textAlignment = .center
        empty.numberOfLines = 0

        [bar, countLabel, table, empty].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: g.topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            countLabel.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4),
            countLabel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 20),
            countLabel.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -20),
            table.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 4),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            empty.leadingAnchor.constraint(greaterThanOrEqualTo: g.leadingAnchor, constant: 32),
        ])
    }

    private func reload() {
        items = store.all()
        countLabel.text = items.isEmpty ? "只保存在这台手机，不上传" :
            "共 \(items.count) 篇 · 点开恢复 · 左滑删除 · 只保存在本机"
        empty.isHidden = !items.isEmpty
        table.isHidden = items.isEmpty
        table.reloadData()
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func clearTapped() {
        guard !items.isEmpty else { return }
        let alert = UIAlertController(title: "清空全部历史？",
            message: "删除后无法恢复，当前编辑中的稿子不会受影响。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            self?.store.removeAll()
            self?.reload()
        })
        present(alert, animated: true)
    }
}

extension ScriptHistoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "history", for: indexPath)
            as! HistoryCell
        cell.configure(items[indexPath.row])
        cell.accessibilityIdentifier = "historyItem.\(indexPath.row)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect?(items[indexPath.row].text)
        dismiss(animated: true)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        let item = items[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") {
            [weak self] _, _, done in
            self?.store.delete(id: item.id)
            self?.reload()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

private final class HistoryCell: UITableViewCell {
    private let name = UILabel()
    private let body = UILabel()
    private let meta = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = DS.panel.withAlphaComponent(0.78)
        layer.cornerRadius = 18
        layer.masksToBounds = true

        name.font = DS.font(.body, weight: .semibold)
        name.textColor = DS.ink
        name.numberOfLines = 1
        body.font = DS.font(.footnote)
        body.textColor = DS.ink2
        body.numberOfLines = 2
        meta.font = DS.font(.caption2)
        meta.textColor = DS.ink3

        let stack = UIStackView(arrangedSubviews: [name, body, meta])
        stack.axis = .vertical
        stack.spacing = 4
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: ScriptHistoryItem) {
        name.text = item.title
        body.text = item.preview
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        meta.text = "\(item.text.count) 字 · \(f.localizedString(for: item.updatedAt, relativeTo: Date()))"
        accessibilityLabel = "\(item.title)，\(item.text.count)字，\(meta.text ?? "")"
        accessibilityTraits = .button
    }
}
