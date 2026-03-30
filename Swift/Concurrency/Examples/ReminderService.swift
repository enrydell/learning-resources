import Combine
import Foundation

final class DefaultReminderService: ReminderService {
    private let dataSource: ReminderDataSource
    
    init(dataSource: ReminderDataSource) {
        self.dataSource = dataSource
    }
    
        // 1. Paradigm: Callback-Based (DispatchGroup para sincronização)
    func fetchReminders(completion: @escaping ([Reminder]) -> Void) {
        let group = DispatchGroup()
        var allReminders: [Reminder] = []
        let lock = NSLock()
        
        for _ in 0 ..< 3 {
            group.enter()
            dataSource.fetchReminders { newReminders in
                lock.lock()
                allReminders.append(contentsOf: newReminders)
                lock.unlock()
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(allReminders)
        }
    }
    
    // OU
    
    func fetchReminders(completion: @escaping ([Reminder]) -> Void) {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "queue")
        var allReminders: [Reminder] = []
        
        for _ in 0 ..< 3 {
            group.enter()
            dataSource.fetchReminders { newReminders in
                queue.async {
                    allReminders.append(contentsOf: newReminders)
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            completion(allReminders)
        }
    }
    
        // 2. Paradigm: Combine (Zip para aguardar múltiplos Publishers)
    func remindersPublisher() -> AnyPublisher<[Reminder], Never> {
        let page1 = Future<[Reminder], Never> { promise in self.dataSource.fetchReminders { promise(.success($0)) } }
        let page2 = Future<[Reminder], Never> { promise in self.dataSource.fetchReminders { promise(.success($0)) } }
        let page3 = Future<[Reminder], Never> { promise in self.dataSource.fetchReminders { promise(.success($0)) } }
        
        return Publishers.Zip3(page1, page2, page3)
            .map { p1, p2, p3 in
                return p1 + p2 + p3
            }
            .eraseToAnyPublisher()
    }
    
    // OU
    
    func remindersPublisher() -> AnyPublisher<[Reminder], Never> {
            // Criamos um array de 3 futures dinamicamente
        let tasks = (1...3).map { _ in
            Future<[Reminder], Never> { promise in
                self.dataSource.fetchReminders { promise(.success($0)) }
            }
        }
        
        return Publishers.MergeMany(tasks)
            .collect()
            .map { $0.flatMap { $0 } }
            .eraseToAnyPublisher()
    }
    
        // 3. Paradigm: Swift Concurrency (TaskGroup para paralelismo estruturado)
    func fetchRemindersAsync() async -> [Reminder] {
        await withTaskGroup(of: [Reminder].self) { group in
                
            for _ in 0..<3 {
                group.addTask {
                    await self.dataSource.fetchReminders()
                }
            }
            
            var allReminders: [Reminder] = []
                
            for await page in group {
                allReminders.append(contentsOf: page)
            }
            
            return allReminders
        }
    }
    
    // OU
    
    func fetchRemindersAsync() async -> [Reminder] {
        await withTaskGroup(of: [Reminder].self) { group in
            for _ in 0..<3 {
                group.addTask { await self.dataSource.fetchReminders() }
            }
            
            return await group.reduce(into: []) { all, page in
                all.append(contentsOf: page)
            }
        }
    }
}

protocol ReminderService: AnyObject {
    func fetchReminders(completion: @escaping ([Reminder]) -> Void)
    func remindersPublisher() -> AnyPublisher<[Reminder], Never>
    func fetchRemindersAsync() async -> [Reminder]
}

protocol ReminderDataSource: AnyObject {
    func fetchReminders(completion: @escaping ([Reminder]) -> Void)
    func fetchReminders() async -> [Reminder]
}
