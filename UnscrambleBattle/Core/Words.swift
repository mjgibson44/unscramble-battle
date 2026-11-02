import Foundation

enum WordBank {
    /// Common English words, 5 to 8 letters.
    static let words: [String] = {
        let raw = """
airplane alphabet anchor angel animal apple asteroid autumn backpack badge baker balloon banana
baseball basket battery beach beard bedroom birthday blade blank blanket blizzard bloom board
bottle brain brave bread breeze brick bridge brother brush bubble bucket building butter button
cabbage cabin calendar camel camera campfire candle candy carpet cartoon castle chair chalk
champion charm chase cheese cherry chess chicken chief chipmunk circle climb clock closet cloud
coast coffee compass computer concert cookie coral cotton couch crane crown crystal cucumber
cupcake curve dairy daisy dance daughter diamond diary dinosaur dolphin dragon dream drink eager
eagle earth edition effect elephant empire engine envelope example factory fairy family fantasy
farmer father feast feather fence festival fiction field finger firework flame flamingo float
flower flute focus football forest fountain freedom friend frontier frost fruit gallery garden
gardener garlic ghost giant ginger giraffe glass globe glove goldfish grain grape grass guard
guest guitar hammer happy harvest heart hedgehog helmet history holiday homework honey horse
hospital hotel house iceberg insect internet island jacket jelly jewel journey juice jungle
kangaroo kettle keyboard kitchen kitten knife ladder ladybug landmark lantern laugh lemon
lemonade leopard library light lizard lobster lucky lunch machine magazine magic mailbox mammoth
mango maple marathon march market meadow medal metal mirror money monkey monster month morning
mother motor mountain mouse museum mushroom music mystery needle network night notebook number
nurse ocean octopus olive onion orange orbit orchard otter paint painter painting palace
pancakes panda panther paper parrot party passage peaceful pearl pencil penguin pepper person
phone piano picture pilgrim pilot pinecone pirates pizza plane planet plant plate platypus
pocket popcorn potato pound power printer prize proud pumpkin pumpkins punch puppy puzzle
pyramid queen question quiet quilt rabbit radio railroad rainbow raincoat raven reptile ridge
river roast robot rocket rooster royal rugby saddle saint salad sandwich sausage scale scarf
scene school science scissors scout seashell seasons shark sheep shell shelter shine shirt shoes
shore shoulder sight silver singer sister skate skeleton skill skirt slice smile smoke snack
snake snowball solar soldier sound space spark sparkler spice spider spinach spine spoon sport
spring squash squirrel stack stamp starfish station steam stomach stone storm strategy stream
student sugar summer sunlight sunrise sunset surprise sweater sweet sword table tablet teacher
teaspoon teeth thousand thumb thunder ticket tiger toast tomato tooth tornado tower train travel
treasure triangle truck trumpet tulip turtle umbrella uncle uniform unity universe vacation
vampire vapor velvet video village violin voice volcano wagon wallet watch water weather whale
wheat wheel whisper whistle window winter witch wizard woman woodland world yacht yellow
yourself youth zebra zipper
"""
        let list = raw
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map { String($0).lowercased() }
            .filter { (5...8).contains($0.count) && $0.allSatisfy { $0.isLetter } }
        return Array(Set(list)).sorted()
    }()

    static let lookup = Set(words)

    /// Shuffles until the result is neither the word itself nor another real word.
    static func scramble(_ word: String) -> String {
        var result = word
        var tries = 0
        repeat {
            result = String(word.shuffled())
            tries += 1
        } while (result == word || lookup.contains(result)) && tries < 60
        return result
    }

    /// The guess always uses the right letters (it comes from the tiles), so any real word counts.
    static func isCorrect(_ guess: String, answer: String) -> Bool {
        guess == answer || lookup.contains(guess)
    }
}

/// Deals words without repeats until the whole list has been used.
struct WordDeck {
    private var pile: [String] = []

    mutating func next() -> String {
        if pile.isEmpty { pile = WordBank.words.shuffled() }
        return pile.removeLast()
    }
}
