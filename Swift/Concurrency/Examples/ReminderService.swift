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
        let lock = NSLock() // Protege o acesso ao array em paralelo
        
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
    
        // 2. Paradigm: Combine (Zip para aguardar múltiplos Publishers)
    func remindersPublisher() -> AnyPublisher<[Reminder], Never> {
            // Criamos 3 Futures (um para cada página)
        let page1 = Future<[Reminder], Never> { promise in self.dataSource.fetchReminders { promise(.success($0)) } }
        let page2 = Future<[Reminder], Never> { promise in self.dataSource.fetchReminders { promise(.success($0)) } }
        let page3 = Future<[Reminder], Never> { promise in self.dataSource.fetchReminders { promise(.success($0)) } }
        
            // Zip combina os resultados e emite quando todos terminarem
        return Publishers.Zip3(page1, page2, page3)
            .map { p1, p2, p3 in
                return p1 + p2 + p3
            }
            .eraseToAnyPublisher()
    }
    
        // 3. Paradigm: Swift Concurrency (TaskGroup para paralelismo estruturado)
    func fetchRemindersAsync() async -> [Reminder] {
        await withTaskGroup(of: [Reminder].self) { group in
                // Dispara as 3 tarefas em paralelo
            for _ in 0..<3 {
                group.addTask {
                    await self.dataSource.fetchReminders()
                }
            }
            
            var allReminders: [Reminder] = []
                // Coleta os resultados conforme terminam
            for await page in group {
                allReminders.append(contentsOf: page)
            }
            
            return allReminders
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
